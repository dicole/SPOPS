package SPOPS::Export::Perl;

# $Id: Perl.pm,v 2.0 2002/03/19 04:00:01 lachoy Exp $

use strict;
use base qw( SPOPS::Export );
use Data::Dumper qw( Dumper );

$SPOPS::Export::Perl::VERSION  = substr(q$Revision: 2.0 $, 10);

my @track = ();

sub create_footer { my $o = Dumper( \@track ); @track = (); return $o; }

sub create_record { push @track, $_[1]; return '' }

1;

__END__

=pod

=head1 NAME

SPOPS::Export::Perl - Dump SPOPS objects to a pure serialized Perl format

=head1 SYNOPSIS

 # See SPOPS::Export

=head1 DESCRIPTION

Just dump a set of SPOPS objects to a perl data structure using
L<Data::Dumper|Data::Dumper>.

=head1 PROPERTIES

No extra ones beyond L<SPOPS::Export|SPOPS::Export>

=head1 METHODS

B<create_record()>

Just track the record to be exported.

B<create_footer()>

Dump all tracked records out using L<Data::Dumper|Data::Dumper>.

=head1 BUGS

This will likely chew up tons of memory if you are exporting lots of
objects.

=head1 TO DO

Nothing known.

=head1 SEE ALSO

L<SPOPS::Import|SPOPS::Import>

L<Data::Dumper|Data::Dumper>

=head1 COPYRIGHT

Copyright (c) 2001-2002 intes.net, inc.. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHORS

Chris Winters <chris@cwinters.com>

=cut