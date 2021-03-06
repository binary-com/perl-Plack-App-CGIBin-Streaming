# NAME

Plack::App::CGIBin::Streaming - allow old style CGI applications to use
the plack streaming protocol

[![Gitter chat](https://badges.gitter.im/binary-com/perl-Plack-App-CGIBin-Streaming.png)](https://gitter.im/binary-com/perl-Plack-App-CGIBin-Streaming)
[![Build Status](https://travis-ci.org/binary-com/perl-Plack-App-CGIBin-Streaming.svg?branch=master)](https://travis-ci.org/binary-com/perl-Plack-App-CGIBin-Streaming)
[![codecov](https://codecov.io/gh/binary-com/perl-Plack-App-CGIBin-Streaming/branch/master/graph/badge.svg)](https://codecov.io/gh/binary-com/perl-Plack-App-CGIBin-Streaming)

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

    Both, `STDIN` and `STDOUT` are configured to use the
    [Plack::App::CGIBin::Streaming::IO](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::IO) PerlIO layer.
    On output, the layer captures the data and sends it to the
    request object. Flushing via `$|` is also supported.
    On input, the layer simply converts calls like `readline STDIN`
    into a method call on the underlying object.

    You can use PerlIO layers to turn the handles into UTF8 mode.
    However, refrain from using a simple `binmode` to reverse the
    effects of a prior `binmode STDOUT, ':utf8'`. This won't pop
    the [Plack::App::CGIBin::Streaming::IO](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::IO) layer but neither
    will it turn off UTF8 mode. This is considered a bug that I don't
    know how to fix. (See also below)

    Reading from `STDIN` using UTF8 mode is also supported.

## Pitfalls and workarounds

### SIGCHLD vs. SIGCLD

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

### binmode

Sometimes one needs to switch STDOUT into UTF8 mode and back. Especially the
_back_ is problematic because the way it is done is often simply
`binmode STDOUT`. Currently, this won't revert the effect of a previous
`binmode STDOUT, ':utf8'`.

Instead use:

    binmode STDOUT, ':bytes';

# EXAMPLE

This distribution contains a complete example in the `eg/` directory.
After building the module by

    perl Build.PL
    ./Build

you can try it out:

    (cd eg && starman -l :5091 --workers=2 --preload-app app.psgi) &

Then you should be able to access

- [http://localhost:5091/clock.cgi?30](http://localhost:5091/clock.cgi?30)
- [http://localhost:5091/flush.cgi](http://localhost:5091/flush.cgi)

The clock example is basically the script displayed above. It works in Firefox.
Other browsers don't support multipart HTTP messages.

The flush example demonstrates filtering. It has been tested wich Chromium
35 on Linux. The script first prints a part of the page that contains the
HTML comment `<!-- FlushHead -->`. The filter recognizes this token
and pushes the page out. You should see a red background and the string
`loading -- please wait`. After 2 seconds the page should turn green and
the string should change to `loaded`.

All of this very much depends on browser behavior. The intent is not to
provide an example that works for all of them. Instead, the capabilities
of this module are shown. You can also test these links with `curl`
instead.

The example PSGI file also configures an `access_log` and an `error_log`.

# AUTHOR

Torsten Förtsch <torsten.foertsch@gmx.net>

# COPYRIGHT

Copyright 2014 Binary.com

# LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). A copy of the full
license is provided by the `LICENSE` file in this distribution and can
be obtained at

[http://www.perlfoundation.org/artistic\_license\_2\_0](http://www.perlfoundation.org/artistic_license_2_0)

# SEE ALSO

- [Plack::App::CGIBin](https://metacpan.org/pod/Plack::App::CGIBin)
- [CGI::Compile](https://metacpan.org/pod/CGI::Compile)
- [Plack::App::CGIBin::Streaming::Request](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::Request)
- [Plack::App::CGIBin::Streaming::IO](https://metacpan.org/pod/Plack::App::CGIBin::Streaming::IO)
