#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <sys/mman.h>
#include <sys/sendfile.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>

#include <evhtp.h>
#include <event2/buffer.h>
#include <event2/bufferevent.h>
#include <event2/http.h>

// TODO app_parent should be renamed to server or similar
static struct
app_parent {
    evhtp_t         * evhtp;
    evbase_t        * evbase;
    PerlInterpreter * perl;
    SV              * perl_app;
    char            * host;
    int               port;
    char            * http_host;
    int               max_reqs;
};

static struct
app {
    struct app_parent * parent;
    evbase_t          * evbase;
    PerlInterpreter   * perl;
    SV                * perl_app;
    SV                * io;
    HV                * io_stash;
    int                 max_reqs;
    int                 reqs_ct;
    /*
    SV                * body_fh;
    size_t              body_sz;
    char                body_sz_c[64];
    int                 body_fd;
    */
};

static struct
req_wrap {
    evhtp_request_t * req;
    SV              * perl_reqvar;
    // TODO rename body to output_body ...
    SV              * body_fh;
    size_t            body_sz;
    char              body_sz_c[64];
    int               body_fd;
    long              input_body_pos;
    struct evbuffer_file_segment * ev_fseg;
};

static void
_init_app(struct app * app) {
    app->perl_app = (SV*)get_cv("_run_app", 0); // it should exist

    app->io_stash = gv_stashpv("Plack::Handler::EVHTP::io", GV_ADD);
    HV* io_obj = newHV();
    SV* io_obj_ref = newRV_noinc((SV*)io_obj);
    app->io = sv_bless(io_obj_ref, app->io_stash);

    app->reqs_ct = 0;
}

static void
_free_app(struct app * app) {
    SvREFCNT_dec(app->io);
}

#ifdef USE_ITHREADS
static void
_clone_perl_context(struct app_parent * app_p, struct app * app) {
    if (app->perl != NULL) {
        PL_perl_destruct_level = 1;
        PERL_SET_CONTEXT(app->perl);
        perl_destruct(app->perl);
        perl_free(app->perl);
    }

    app->perl = perl_clone(app_p->perl, CLONEf_KEEP_PTR_TABLE);

    PERL_SET_CONTEXT(app->perl);

    _init_app(app);

    PERL_SET_CONTEXT(app_p->perl);
}
#endif

static evthr_t *
_request_get_thread(evhtp_request_t * request) {
    evhtp_connection_t * htpconn = evhtp_request_get_connection(request);
    return  htpconn->thread;
}

static char *
_psgi_header_key(evhtp_header_t * header) {
    const int pre_len = 5; // "HTTP_" length
    char * psgi_header = (char*)calloc(sizeof(char) * (header->klen + pre_len + 1), 1);
    memcpy(psgi_header, "HTTP_", pre_len);

    int i = 0;
    while (header->key[i]) {
        if (header->key[i] == '-') {
            psgi_header[i+pre_len] = '_';
        } else {
            psgi_header[i+pre_len] = toupper(header->key[i]);
        }
        i++;
    }
    psgi_header[i+pre_len] = '\0';
    return psgi_header;
}

static int
_psgi_headers(evhtp_header_t * header, void * arg) {
    const int pre_len = 5; // "HTTP_" length
    HV* env = arg;

    if (strcmp(header->key, "Content-Type") == 0) {
        hv_store(env, "CONTENT_TYPE", 12, newSVpv(header->val, header->vlen), 0);
    } else if (strcmp(header->key, "Content-Length") == 0) {
        hv_store(env, "CONTENT_LENGTH", 14, newSViv(atoi(header->val)), 0);
    } else {
        char * psgi_header_key = _psgi_header_key(header);
        SV* env_header_val = *hv_fetch(env, psgi_header_key, pre_len + header->klen, 1);
        if (SvOK(env_header_val)) {
            sv_catpvn(env_header_val, ",", 1);
            sv_catpvn(env_header_val, header->val, header->vlen);
        } else {
            sv_setpvn(env_header_val, header->val, header->vlen);
        }
        free(psgi_header_key);
    }
    return 0;
}

static evhtp_res
_request_header_hook(evhtp_request_t * req, evhtp_header_t * header, void * arg) {
    if (evhtp_header_find(req->headers_in, header->key)) {
        fprintf(stderr, "Key: %s, Val: %s\n", header->key, header->val);
    }
    return EVHTP_RES_OK;
}

static evhtp_res
_request_fini_hook(evhtp_request_t * req, void * arg) {
    struct req_wrap * req_wrap = (struct req_wrap *)arg;

    //if (!SvOK(req_wrap->body_fh))
    //    return;

    /* for sendfile... control response errors (ex. EAGAIN)... AND MAKE IT PORTABLE... */
    //ssize_t out = sendfile((int)req->conn->sock, req_wrap->body_fd, 0, req_wrap->body_sz);
    int zero = 0;
    setsockopt(req->conn->sock, IPPROTO_TCP, TCP_CORK, (void *)&zero, sizeof(zero));

/*    if (out <= 0) {
        fprintf(stderr, "error reserving space: %s\n", strerror(errno));
        return;
    }
*/
}

static void
_response_read_array(evhtp_request_t * req, SV* body) {
    STRLEN len;
    const char *content;
    I32 res_c_len = av_len((AV*)body);

    int i;
    for (i = 0; i <= res_c_len; i++) {
        content = SvPV(*av_fetch((AV*)body, i, 0), len);
        evbuffer_add(req->buffer_out, content, (int)len);
    }
}

static void
_response_read_io(evhtp_request_t * req, SV* body) {
    // TODO
    // Servers MAY check if the body is a real filehandle using fileno and Scalar::Util::reftype
    // Servers SHOULD set the $/ special variable to the buffer size when reading content from $body using the getline

    dSP;

    ENTER;
    SAVETMPS;

    HV* io_stash = SvSTASH(body);
    SV* getline_sv = (SV*)GvCV(gv_fetchmethod(io_stash, "getline"));

    int count;
    SV* body_ref;
    SV* res;
    char* content;
    int leave = 0;
    STRLEN len;

    body_ref = sv_2mortal(newRV_inc(body));
    do {
        PUSHMARK(SP);
        XPUSHs(body_ref);
        PUTBACK;

        count = call_sv(getline_sv, G_EVAL);

        SPAGAIN;

        if (SvTRUE(*PL_stack_sp)) {
            res = POPs;
            content = SvPVx(res, len);
            evbuffer_add(req->buffer_out, content, (int)len);
        } else {
            POPs;
            leave = 1;
        }

        PUTBACK;
    } while ( !leave );


    FREETMPS;
    LEAVE;
}


static void
_send_response(struct req_wrap * req_wrap, AV* res, struct app * app) {
    evhtp_request_t * req = req_wrap->req;
    // TODO make array checks
    I32 res_len = av_len(res);
    /* status code */ 
    IV res_code = SvIV(*av_fetch(res, 0, 0));

    /* headers */
    char empty[] = "";
    AV* res_headers = (AV*)SvRV(*av_fetch(res, 1, 0));
    I32 res_h_len = av_len(res_headers);
    int i;
    for (i = 0; i <= res_h_len; i+=2) {
        SV* sv_key = *av_fetch(res_headers, i, 0);
        SV* sv_val = *av_fetch(res_headers, i+1, 0);
        char* key = SvOK(sv_key) ? SvPV_nolen(sv_key) : empty;
        char* val = SvOK(sv_val) ? SvPV_nolen(sv_val) : empty;
        evhtp_headers_add_header(req->headers_out, evhtp_header_new(key, val, 0, 0));
    }
    evhtp_headers_add_header(req->headers_out, evhtp_header_new("Server", "Plack::Handler::EVHTP", 0, 0));


    /* body */
    // FIXME set TCP_NODELAY on socket creation
    int one = 1;
    setsockopt(req->conn->sock, IPPROTO_TCP, TCP_NODELAY, (void *)&one, sizeof(one));

    SV* body;
    if (res_len == 2) {
        SV* body_ref = *av_fetch(res, 2, 0);
        body = SvRV(body_ref);
    } else {
        // undefined body && write headers and (use writer)
        evhtp_send_reply_chunk_start(req, res_code);
        evbuffer_unfreeze(bufferevent_get_output(req->conn->bev), 1);
        evbuffer_write(bufferevent_get_output(req->conn->bev), req->conn->sock);
        return;
    }

    //int free_req_wrap = 1;
    switch (SvTYPE(body)) {
        case SVt_PVAV:
            _response_read_array(req, body);
            break;
        case SVt_PVGV:
            req_wrap->body_fh = SvREFCNT_inc(body);

            PerlIO* res_io = IoIFP(sv_2io(body));

            PerlIO_seek(res_io, 0, SEEK_END);
            req_wrap->body_sz = PerlIO_tell(res_io);
            PerlIO_seek(res_io, 0, SEEK_SET);
            req_wrap->body_fd = PerlIO_fileno(res_io);

            // mmap disabled for now...
            // TODO check why libevent used mmap when sendfile was available
            req_wrap->ev_fseg = evbuffer_file_segment_new(req_wrap->body_fd, 0, req_wrap->body_sz, EVBUF_FS_DISABLE_MMAP);
            evbuffer_add_file_segment(req->buffer_out, req_wrap->ev_fseg, 0, req_wrap->body_sz);
            evbuffer_file_segment_free(req_wrap->ev_fseg);

            if (!evhtp_header_find(req->headers_out, "Content-Length")) {
                evhtp_modp_sizetoa(req_wrap->body_sz, req_wrap->body_sz_c);
                evhtp_headers_add_header(req->headers_out, evhtp_header_new("Content-Length", req_wrap->body_sz_c, 0, 1));
            }
            //setsockopt(req->conn->sock, IPPROTO_TCP, TCP_CORK, (void *)&one, sizeof(one));
            //evhtp_set_hook(&req->hooks, evhtp_hook_on_request_fini, _request_fini_hook, req_wrap);

            break;
        case SVt_PVMG:
            _response_read_io(req, body);
            break;
    }
    evhtp_send_reply(req, res_code);
    free(req_wrap);
}

static HV*
_create_env_hash(struct req_wrap * req_wrap, struct app * app) {
    /* psgi env hash */
    HV* env = newHV();

    evhtp_request_t * req = req_wrap->req;
    struct app_parent * app_p = app->parent;

    SV* method = newSVpv(htparser_get_methodstr_m(req->method), 0);
    hv_store(env, "REQUEST_METHOD", 14, method, 0);

    hv_store(env, "SCRIPT_NAME", 11, newSVpv("", 0), 0);

    //TODO use string length from uridecode
    char* path_decoded = evhttp_uridecode(req->uri->path->full, 0, NULL);
    SV* path_info = newSVpv(path_decoded, 0);
    free(path_decoded);
    hv_store(env, "PATH_INFO", 9, path_info, 0);

    SV* request_uri = newSVpv(req->uri->path->full, 0);
    if (req->uri->query_raw && req->uri->query_raw[0] != "\0") {
        sv_catpv(request_uri, "?");
        sv_catpv(request_uri, req->uri->query_raw);
    }
    hv_store(env, "REQUEST_URI", 11, request_uri, 0);

    SV* query_string = req->uri->query_raw ?
        newSVpv(req->uri->query_raw, 0) :
        newSVpv("", 0);
    hv_store(env, "QUERY_STRING", 12, query_string, 0);

    hv_store(env, "SERVER_NAME", 11, newSVpv(app_p->host, 0), 0);
    hv_store(env, "SERVER_PORT", 11, newSViv(app_p->port), 0);
    hv_store(env, "HTTP_HOST",    9, newSVpv(app_p->http_host,0), 0);

    switch (req->uri->scheme) {
        case htp_scheme_https:
            hv_store(env, "psgi.url_scheme", 15, newSVpv("https", 5), 0);
            break;
        default:
            hv_store(env, "psgi.url_scheme", 15, newSVpv("http", 4), 0);
            break;
    }

    switch (req->proto) {
        case EVHTP_PROTO_11:
            hv_store(env, "SERVER_PROTOCOL", 15, newSVpv("HTTP/1.1", 8), 0);
            break;
        case EVHTP_PROTO_10:
            hv_store(env, "SERVER_PROTOCOL", 15, newSVpv("HTTP/1.0", 8), 0);
            break;
        default:
            hv_store(env, "SERVER_PROTOCOL", 15, newSVpv("HTTP/1.0", 8), 0);
            break;
    }

    evhtp_headers_for_each(req->headers_in, _psgi_headers, env);

    hv_store(env, "psgix.input.buffered", 20, newSViv(1), 0);
    SV* req_wrap_ref = sv_bless((SV*)newRV_noinc(newSViv(PTR2IV(req_wrap))), app->io_stash);
    hv_store(env, "psgi.input", 10, req_wrap_ref, 0);

    hv_store(env, "psgi.multithread",  16, newSViv(0), 0);
    hv_store(env, "psgi.multiprocess", 17, newSViv(1), 0);
    hv_store(env, "psgi.run_once",     13, newSViv(0), 0);
    hv_store(env, "psgi.streaming",    14, newSViv(1), 0);
    hv_store(env, "psgi.nonblocking",  16, newSViv(0), 0);

    return env;
}

static void
_response_callback(struct req_wrap * req_wrap, SV* res, struct app * app) {
    evhtp_request_t * req = req_wrap->req;
    switch (SvTYPE(res)) {
        case SVt_PVAV:
            _send_response(req_wrap, (AV*)res, app);
            break;
    }
}

static void
_request_generic_callback(evhtp_request_t * req, void * arg) {
    evthr_t            * thread;
    struct app         * app;

    if (arg) {
        app = (struct app *)arg;
    } else {
        thread = _request_get_thread(req);
        app = evthr_get_aux(thread);
    }
    struct app_parent  * app_p  = app->parent;


    struct req_wrap    * req_wrap = calloc(sizeof(struct req_wrap), 1);
    req_wrap->req = req;
    req_wrap->input_body_pos = 0;

#ifdef USE_ITHREADS
    if (app->max_reqs > 0 && app->reqs_ct >= app->max_reqs) {
        _clone_perl_context(app_p, app);
    }
#endif
    app->reqs_ct++;

    PERL_SET_CONTEXT(app->perl);

    dSP;

    HV* env = _create_env_hash(req_wrap, app);

    int count;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    SV* env_ref = sv_2mortal(newRV_noinc((SV*) env));
    SV* app_ref = sv_2mortal((SV*)newRV_noinc(newSViv(PTR2IV(app))));
    SV* req_wrap_ref = sv_bless(sv_2mortal((SV*)newRV_noinc(newSViv(PTR2IV(req_wrap)))), app->io_stash);

    XPUSHs(env_ref);
    XPUSHs(app_ref);
    XPUSHs(req_wrap_ref);
    PUTBACK;

    count = call_sv(app->perl_app, G_EVAL|G_SCALAR|G_KEEPERR);

    SPAGAIN;

    if (!SvTRUE(ERRSV)) {
        SV* res_rv = POPs;
        if (SvROK(res_rv)) {
            SV* res = SvRV(res_rv);
            _response_callback(req_wrap, res, app);
        } else {
            // not a reference raise error...
        }
    } else {
        POPs;
        evhtp_headers_add_header(req->headers_out, evhtp_header_new("Content-Length", "0", 0, 1));
        evhtp_send_reply(req, EVHTP_RES_500);
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
}

static evhtp_res
_set_conn_hooks(evhtp_connection_t * conn, void * arg) {
    //evhtp_set_hook(&conn->hooks, evhtp_hook_on_header, _request_header_hook, NULL);
    return EVHTP_RES_OK;
}

/* PERL FUNCTIONS */

void
send_response(SV* req_wrap_ref, AV* res, SV* app_ref, SV* reqvar) {
    struct req_wrap * req_wrap = INT2PTR(evhtp_request_t*, SvIV(SvRV(req_wrap_ref)));
    evhtp_request_t * req = req_wrap->req;

    if (SvOK(reqvar))
        req_wrap->perl_reqvar = SvREFCNT_inc(reqvar);

    struct app * app = INT2PTR(struct app*, SvIV(SvRV(app_ref)));
    _send_response(req_wrap, res, app);
}

int
read_body(SV* req_wrap_ref, SV* perl_buf, size_t len, size_t offset) {
    int r;
    char* s;

    struct req_wrap * req_wrap = INT2PTR(struct req_wrap *, SvIV(SvRV(req_wrap_ref)));
    evhtp_request_t* req = req_wrap->req;

    struct evbuffer* buffer_in = req->buffer_in;
    struct evbuffer_ptr ptr;
    struct evbuffer_iovec v[1];
    long n_read = 0;

    if (evbuffer_ptr_set(buffer_in, &ptr, req_wrap->input_body_pos, EVBUFFER_PTR_SET) < 0)
        return;

    if (!SvOK(perl_buf))
        sv_setpvn(perl_buf, "", 0);

    size_t perl_buf_len = (size_t)sv_len(perl_buf);
    (void)SvPVbyte_force(perl_buf, perl_buf_len);

    if (offset > perl_buf_len) {
        s = SvGROW(perl_buf, offset+1);
        Zero(s + perl_buf_len*sizeof(char), offset - perl_buf_len, char);
    }
    SvCUR_set(perl_buf, offset);

    while (n_read < len) {
        if (evbuffer_peek(buffer_in, -1, &ptr, v, 1) < 1)
            break;

        int n_to_read = len - n_read;
        if (n_to_read > v[0].iov_len)
            n_to_read = v[0].iov_len;
            s = SvGROW(perl_buf, offset + n_read + n_to_read + 1);
            sv_catpvn(perl_buf, v[0].iov_base, n_to_read);
            n_read += n_to_read;
            SvCUR_set(perl_buf, offset + n_read);

        /* Advance the pointer so we see the next chunk next time. */
        if (n_to_read < v[0].iov_len || evbuffer_ptr_set(buffer_in, &ptr, v[0].iov_len, EVBUFFER_PTR_ADD) < 0)
            break;
    }
    req_wrap->input_body_pos += n_read;
    s[offset + n_read] = '\0';
    SvPOK_only(perl_buf);
    SvSETMAGIC(perl_buf);

    return n_read;
}

int
seek_body(SV* req_wrap_ref, long offset, int whence) {
    struct req_wrap * req_wrap = INT2PTR(struct req_wrap *, SvIV(SvRV(req_wrap_ref)));
    struct evbuffer* buffer_in = req_wrap->req->buffer_in;

    size_t buf_len = evbuffer_get_length(buffer_in);
    long new_pos = req_wrap->input_body_pos;

    switch (whence) {
        case SEEK_SET:
            new_pos = offset;
            break;
        case SEEK_CUR:
            new_pos += offset;
            break;
        case SEEK_END:
            new_pos = buf_len + offset;
            break;
        default:
            return 0;
    }
    if (new_pos > 0 && new_pos <= buf_len) {
        req_wrap->input_body_pos = new_pos;
        return 1;
    } else {
        return 0;
    }
}

int
write_body(SV* req_wrap_ref, SV* content_ref) {
    struct req_wrap * req_wrap = INT2PTR(struct req_wrap *, SvIV(SvRV(req_wrap_ref)));
    evhtp_request_t* req = req_wrap->req;

    struct evbuffer *buffer_out = req->buffer_out;
    char* content;
    STRLEN len;
    content = SvPVx(content_ref, len);

    evbuffer_add(buffer_out, content, (int)len);
    evhtp_send_reply_chunk(req, buffer_out);
    evbuffer_drain(buffer_out, -1);
    evbuffer_write(bufferevent_get_output(req->conn->bev), req->conn->sock);
}

void
end_reply(SV* req_wrap_ref) {
    struct req_wrap * req_wrap = INT2PTR(struct req_wrap *, SvIV(SvRV(req_wrap_ref)));
    evhtp_request_t* req = req_wrap->req;

    evhtp_send_reply_chunk_end(req);
}

SV*
get_reqvar(SV* req_wrap_ref) {
    struct req_wrap * req_wrap = INT2PTR(struct req_wrap *, SvIV(SvRV(req_wrap_ref)));
    return req_wrap->perl_reqvar;
}

#ifdef USE_ITHREADS
static void
_app_init_thread(evhtp_t * htp, evthr_t * thread, void * arg) {
    struct app_parent * app_p = arg;
    struct app        * app   = calloc(sizeof(struct app), 1);

    app->parent   = app_p;
//    app->evbase   = evthr_get_base(thread);
    app->max_reqs = app_p->max_reqs;

    _clone_perl_context(app_p, app);
    evthr_set_aux(thread, app);
}
#endif

static void
sigint(int sig, short why, void * data) {
    event_base_loopexit(data, NULL);
}

void
start_server(SV* perl_app, char* host, int http_port, int n_threads, int max_reqs) {
    struct event      * ev_sigint;
    struct app_parent * app_p = calloc(sizeof(struct app_parent), 1);
    struct app        * app   = calloc(sizeof(struct app), 1);
    //TODO check where http_host is being set
    char              http_host[50];

    evbase_t * evbase = event_base_new();
    evhtp_t  * evhtp  = evhtp_new(evbase, NULL);

    app_p->evhtp            = evhtp;
    app_p->evbase           = evbase;
    app_p->perl             = get_context();
    app_p->perl_app         = perl_app; // TODO make it work without threads
    app_p->host             = host;
    app_p->port             = http_port;
    app_p->max_reqs         = max_reqs;

    app_p->http_host = http_host;

    evhtp_set_post_accept_cb(evhtp, _set_conn_hooks, NULL);

#ifdef USE_ITHREADS
    if (n_threads > 1) {
        evhtp_set_gencb(evhtp, _request_generic_callback, NULL);
        evhtp_use_threads(evhtp, _app_init_thread, n_threads, app_p);
    } else {
#endif
        app->parent     = app_p;
        app->perl       = app_p->perl;
        app->max_reqs   = 0; // TODO make max_requests work for one thread (but without using clone that depends on multi-threaded compiled perl)
        _init_app(app);
        evhtp_set_gencb(evhtp, _request_generic_callback, app);
#ifdef USE_ITHREADS
    }
#endif
    evhtp_bind_socket(evhtp, host, http_port, 1024);

    //ev_sigint = evsignal_new(evbase, SIGINT, sigint, evbase);
    //evsignal_add(ev_sigint, NULL);

    event_base_loop(evbase, 0);

    event_free(ev_sigint);
    evhtp_unbind_socket(evhtp);

    // TODO check this stuff
    if (n_threads <= 1) {
        _free_app(app);
    }
    free(app_p);
    free(app);

    evhtp_free(evhtp);
    event_base_free(evbase);

}
