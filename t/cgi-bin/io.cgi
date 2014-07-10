#!/usr/bin/perl

use strict;
use warnings;

BEGIN {push @main::loaded, __FILE__}

print <<'EOF';
Status: 200
Content-Type: text/plain

EOF

my $len=0;
{
    local $/=\100;
    while (defined(my $chunk=<STDIN>)) {
        $len+=length $chunk;
        print $chunk;
    }
}

print ("\n\nlength: $len\nmethod: $ENV{REQUEST_METHOD}\n");
