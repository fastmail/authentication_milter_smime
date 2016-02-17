package Mail::Milter::Authentication::SMIME;
use strict;
use warnings;
use version; our $VERSION = version->declare('v1.0.2');

1;

__END__

=head1 NAME

Mail::Milter::Authentication::SMIME - A Perl Mail Authentication Milter smime handler modules

=head1 DESCRIPTION

Additional handlers for Authentication Milter which did not fit within the core functionality, or
are not yet 100% production ready.

=head1 SYNOPSIS

This is a collection of additional handler modules for Authentication Milter.

Please see the output of 'authentication_milter --help' for usage help.

=head1 DEPENDENCIES

  Mail::Milter::Authentication

=head1 AUTHORS

Marc Bradshaw E<lt>marc@marcbradshaw.netE<gt>

=head1 COPYRIGHT

Copyright 2016

This library is free software; you may redistribute it and/or
modify it under the same terms as Perl itself.
