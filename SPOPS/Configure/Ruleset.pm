package SPOPS::Configure::Ruleset;

# $Id: Ruleset.pm,v 3.0 2002/08/28 01:16:29 lachoy Exp $

use strict;
use SPOPS qw( _w DEBUG );

$SPOPS::Configure::Ruleset::VERSION  = sprintf("%d.%02d", q$Revision: 3.0 $ =~ /(\d+)\.(\d+)/);

sub create_relationship {
    die "SPOPS::Configure::Ruleset is deprecated -- please see the docs for SPOPS::ClassFactory.\n";
}

1;

=pod

=head1 NAME

SPOPS::Configure::Ruleset - DEPRECATED

=head1 SYNOPSIS

See L<SPOPS::ClassFactory|SPOPS::ClassFactory>

=head1 DESCRIPTION

THIS CLASS IS DEPRECATED. DO NOT USE IT. If you try to call its only
method from before ('create_relationship()') a C<die> will be called
with a deprecation message. You probably should not have been calling
this directly anyway :-)

=head1 COPYRIGHT

Copyright (c) 2001-2002 intes.net, inc.. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHORS

Chris Winters  <chris@cwinters.com>

=cut



