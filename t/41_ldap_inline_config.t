# -*-perl-*-

# $Id: 41_ldap_inline_config.t,v 1.1 2002/09/09 12:39:59 lachoy Exp $

use strict;
use constant NUM_TESTS       => 4;

my $SPOPS_CLASS = 'LDAPInlineTest';

my ( $db, $do_end );

{
    # Read in the config file and make sure we're supposed to run

    do "t/config.pl";
    my $config = _read_config_file() || {};
    unless ( $config->{LDAP_base_dn} and $config->{LDAP_host} ) {
        print "1..0\n";
        print "Skipping test on this platform\n";
        exit;
    }

    $do_end++;

    require Test::More;
    Test::More->import( tests => NUM_TESTS );

    require_ok( 'SPOPS::Initialize' );

    # Initialize our classes

    my $USER_LDAP_CLASS  = 'LDAP_User';
    my $GROUP_LDAP_CLASS = 'LDAP_Group';
    my $TEST_OU          = 'ou=SPOPSTest';
    my $USER_OU          = "ou=Users";
    my $BASE_DN          = "$TEST_OU,$config->{LDAP_base_dn}";
    my $USER_BASE_DN     = "$USER_OU,$BASE_DN";
    my $spops_config = {
         user => {
             ldap_base_dn => $USER_BASE_DN,
             class        => $USER_LDAP_CLASS,
             rules_from   => [ 'SPOPS::Tool::LDAP::Datasource' ],
             isa          => [ 'SPOPS::LDAP' ],
             field        => [ qw/ uid cn sn givenname mail objectclass / ],
             id_field     => 'uid',
             id_value_field => 'mail',
             field_map    => { user_id => 'uid', first_name => 'givenname' },
             multivalue   => [ 'objectclass' ],
             ldap_object_class => [ qw/ top person inetOrgPerson organizationalPerson / ],
             ldap_fetch_object_class => 'person',
             ldap_config  => {
                   host    => $config->{LDAP_host},
                   port    => $config->{LDAP_port},
                   bind_dn => $config->{LDAP_bind_dn},
                   bind_password => $config->{LDAP_bind_password},
             },
         },
    };
    my $class_init_list = eval { SPOPS::Initialize->process({ config => $spops_config }) };
    ok( ! $@, 'Initialize process run' );
    is( $class_init_list->[0], $SPOPS_CLASS, 'Initialize class' );

    my $ldap = $SPOPS_CLASS->global_datasource_handle;
    ok( UNIVERSAL::isa( $ldap, 'Net::LDAP' ), 'Retrieved datasource from class' );
}
