requires 'perl', '5.010';

requires 'Plack', '0.9989';
requires 'CGI::Compile', '0.17';
requires 'PerlIO::via', '0.11';

on test => sub {
    requires 'Test::More', '0.88';
};
