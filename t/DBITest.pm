package DBITest;

# $Id: DBITest.pm,v 1.3 2000/11/18 21:09:05 cwinters Exp $

use strict;
use SPOPS::DBI;
use SPOPS::Error;

@DBITest::ISA      = qw( SPOPS::DBI );
$DBITest::C        = {
 class        => 'DBITest',
 field_list   => [ qw/ spops_id spops_name spops_goop spops_num / ],
 id_field     => 'spops_id',
 skip_undef   => { spops_num => 1 },
 sql_defaults => [ qw/ spops_num / ],
 base_table   => 'spops_test',
 table_name   => 'spops_test',
};
$DBITest::C->{field} = { map { $_ => 1 } @{ $DBITest::C->{field_list} } };
$DBITest::RULESET  = {};

sub CONFIG  { return $DBITest::C };
sub RULESET { return $DBITest::RULESET };

# We use this for DBD drivers known not to work with the $sth->{TYPE}
# property
sub _assign_types {
 my $class = shift;
 $DBITest::C->{dbi_type_info} = { spops_id => 'num', spops_name => 'char',
                                  spops_goop => 'char', spops_num => 'num' };
}

1;

