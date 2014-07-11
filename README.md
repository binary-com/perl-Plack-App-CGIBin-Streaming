# NAME

Plack::App::CGIBin::Streaming - allow old style CGI applications to use
the plack streaming protocol

# SYNOPSIS

in your `app.psgi`:

    use Plack::App::CGIBin::Streaming;

    Plack::App::CGIBin::Streaming->new(root=>...)->to_app;

# DESCRIPTION

With [Plack](https://metacpan.org/pod/Plack) already comes [Plack::App::CGIBin](https://metacpan.org/pod/Plack::App::CGIBin).
`Plack::App::CGIBin::Streaming` serves a very similar purpose.

So, why do I need another module? The reason is that [Plack::App::CGIBin](https://metacpan.org/pod/Plack::App::CGIBin)
first collects all the output from your CGI scripts before it prints the
first byte to the client. This renders the following simple clock script
useless:

    use strict;
    use warnings;

    $|=0;

    my $boundary='The Final Frontier';
    print <<"EOF";
    Status: 200
    Content-Type: multipart/x-mixed-replace;boundary="$boundary";

    EOF

    $boundary="--$boundary\n";

    my $mpheader=<<'HEADER';
    Content-type: text/html; charset=UTF-8;

    HEADER

    for(1..100) {
        print ($boundary, $mpheader,
               '<html><body><h1>'.localtime()."</h1></body></html>\n");
        $|=1; $|=0;
        sleep 1;
    }

    print ($boundary);

Although multipart HTTP messages are quite exotic, there are situations
where you rather want to prevent this buffering. If your document is very
large for example, each instance of your plack server allocates the RAM
to buffer it. Also, you might perhaps send out the `<head>` section
of your HTTP document as fast as possible to enable the browser load JS and
CSS while the plack server is still busy with producing the actual document.

`Plack::App::CGIBin::Streaming` compiles the CGI scripts using
[CGI::Compile](https://metacpan.org/pod/CGI::Compile) and provides a runtime environment similar to
`Plack::App::CGIBin`. Compiled scripts are cached. For production
environments, it is possible to precompile and cache scripts at server
start time, see the `preload` option below.

Every single request is represented as an object that inherits from
[Plack::App::CGIBin::Streaming::Request](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::Request). This class mainly provides
means for handling response headers and body.

## Options

The plack app is built as usual:

    $app=Plack::App::CGIBin::Streaming->new(@options)->to_app;

`@options` is a list of key/value pairs configuring the app. The
`Plack::App::CGIBin::Streaming` class inherits from [Plack::App::File](https://metacpan.org/pod/Plack::App::File).
So, everything recognized by this class is accepted. In particular, the
`root` parameter is used to specify the directory where your CGI programs
reside.

Additionally, these parameters are accepted:

- request\_class

    specifies the class of the request object to construct for every request.
    This class should implement the interface described in
    [Plack::App::CGIBin::Streaming::Request](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::Request). Best if your request class
    inherits from [Plack::App::CGIBin::Streaming::Request](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::Request).

    This parameter is optional. By default
    `Plack::App::CGIBin::Streaming::Request` is used.

- request\_params

    specifies a list of additional parameters to be passed to the request
    constructor.

    By default the request constructor is passed 2 parameters. This list is
    appended to the parameter list like:

        $R = $class->new(
            env => $env,
            responder => $responder,
            @{$self->request_params//[]},
        );

- preload

    In a production environment, you probably want to use a (pre)forking server
    to run the application. In this case is is sensible to compile as much
    perl code as possible at server startup time by the parent process because
    then all the children share the RAM pages where the code resides (by
    copy-on-write) and you utilize your server resources much better.

    One way to achieve that is to keep your CGI applications very slim and put
    all the actual work into modules. These modules are then `use`d or
    `require`d in your `app.psgi` file.

    As a simpler alternative you can specify a list of `glob` patterns as
    `preload` value. `Plack::App::CGIBin::Streaming` will then load and
    compile all the scripts matching all the patterns when the app object is
    created.

    This technique has benefits and drawbacks:

    - pro: more concurrent worker children in less RAM

        see above

    - con: no way to reload the application on the fly

        when your scripts change you have to restart the server. Without preloading
        anything you could just kill all the worker children (or signal them to do
        so after the next request).

    - pro/con: increased privileges while preloading

        the HTTP standard port is 80 and, thus, requires root privileges to bind to.
        scripts are preloaded before the server opens the port. So, even if it later
        drops privilges, at preload time you still are root.

## Runtime environment

Additional to the environment provided by [CGI::Compile](https://metacpan.org/pod/CGI::Compile), this module
provides:

- the global variable `$Plack::App::CGIBin::Streaming::R`

    For the request lifetime it contains the actual request object. This variable
    is `local`ized. There is also a way to access this variable as class method.

    If you use a [Coro](https://metacpan.org/pod/Coro) based plack server, make sure to replace the guts
    of this variable when switching threads, see `swap_sv()` in [Coro::State](https://metacpan.org/pod/Coro::State).

- `Plack::App::CGIBin::Streaming->request` or
`Plack::App::CGIBin::Streaming::request`

    This function/method returns the current request object or `undef` if
    called outside the request loop.

- `%ENV` is populated

    everything from the plack environment except keys starting with `plack`
    or `psgi.` is copied to `%ENV`.

- `STDIN` and `STDOUT`

    `STDIN` depends on the plack server implementation. It is simply an
    alias for the `psgi.input` PSGI environment element.

    `STDOUT` is configured using the [Plack::App::CGIBin::Streaming::IO](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::IO) PerlIO
    layer to capture output. The layer sends the output to the request object.
    Flushing via `$|` is also supported.

## Pitfalls and workarounds

During the implementation I found a wierd bug. At least on Linux, perl
supports `CHLD` and `CLD` as name of the signal that is sent when a child
process exits. Also, when Perl calls a signal handler, it passes the signal
name as the first parameter. Now the question arises, which name is passed
when a child exits. As it happens the first assignment to `%SIG{CHLD}`
or `$SIG{CLD}` determines that name for the rest of the lifetime of the
process. Now, several plack server implementations, e.g. [Starman](https://metacpan.org/pod/Starman),
rely on that name to be `CHLD`.

As a workaround, `Plack::App::CGIBin::Streaming` contains this code:

    BEGIN {
        local $SIG{CHLD}=$SIG{CHLD};
    }

If your server dies when it receives a SIGCHLD, perhaps the module is loaded
too late.

# AUTHOR

Torsten Förtsch <torsten.foertsch@gmx.net>

# COPYRIGHT

Copyright 2014 Binary.com

# LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a copy
of the full license at:

[http://www.perlfoundation.org/artistic\_license\_2\_0](http://www.perlfoundation.org/artistic_license_2_0)

# SEE ALSO

- [Plack::App::CGIBin](https://metacpan.org/pod/Plack::App::CGIBin)
- [CGI::Compile](https://metacpan.org/pod/CGI::Compile)
- [Plack::App::CGIBin::Streaming::Request](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::Request)
- [Plack::App::CGIBin::Streaming::IO](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::IO)
