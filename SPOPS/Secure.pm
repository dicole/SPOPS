package SPOPS::Secure;

# $Id: Secure.pm,v 1.1.1.1 2001/02/02 06:08:26 lachoy Exp $

use strict;
use vars         qw( $EMPTY );
use Data::Dumper qw( Dumper );
require Exporter;

@SPOPS::Secure::ISA     = qw( Exporter );
$SPOPS::Secure::VERSION = sprintf("%d.%02d", q$Revision: 1.1.1.1 $ =~ /(\d+)\.(\d+)/);

# Stuff for security constants and exporting

use constant SEC_LEVEL_NONE          => 1;
use constant SEC_LEVEL_READ          => 4;
use constant SEC_LEVEL_WRITE         => 8;

use constant SEC_LEVEL_NONE_VERBOSE  => 'NONE';
use constant SEC_LEVEL_READ_VERBOSE  => 'READ';
use constant SEC_LEVEL_WRITE_VERBOSE => 'WRITE';

use constant SEC_SCOPE_USER          => 'u';
use constant SEC_SCOPE_GROUP         => 'g';
use constant SEC_SCOPE_WORLD         => 'w';

# Weird referential thing goes on when we try to being in SPOPS, which
# tries to being in SPOPS::Secure, which tries to bring in SPOPS
# (since previously we had "use SPOPS qw( _w );"). So we have to this
# ugly thing or do an 'import()' directly.

*_w = *SPOPS::_w;

@SPOPS::Secure::EXPORT_OK = qw(
 $EMPTY
 SEC_LEVEL_NONE SEC_LEVEL_READ SEC_LEVEL_WRITE
 SEC_SCOPE_USER SEC_SCOPE_GROUP SEC_SCOPE_WORLD
 SEC_LEVEL_NONE_VERBOSE SEC_LEVEL_READ_VERBOSE SEC_LEVEL_WRITE_VERBOSE 
);

%SPOPS::Secure::EXPORT_TAGS = (
 all     => [ qw/ SEC_LEVEL_NONE SEC_LEVEL_READ SEC_LEVEL_WRITE 
                  SEC_SCOPE_USER SEC_SCOPE_GROUP SEC_SCOPE_WORLD
                  SEC_LEVEL_NONE_VERBOSE SEC_LEVEL_READ_VERBOSE SEC_LEVEL_WRITE_VERBOSE / ],
 scope   => [ qw/ SEC_SCOPE_USER SEC_SCOPE_GROUP SEC_SCOPE_WORLD / ],
 level   => [ qw/ SEC_LEVEL_NONE SEC_LEVEL_READ SEC_LEVEL_WRITE / ],
 verbose => [ qw/ SEC_LEVEL_NONE_VERBOSE SEC_LEVEL_READ_VERBOSE SEC_LEVEL_WRITE_VERBOSE / ],
);


# Dummy (empty) hashref to pass back if we need to 
# basically deny the request -- e.g., they asked for a
# user that isn't an object, they asked for the current
# user and there is none, etc.

$EMPTY = { 
 SEC_SCOPE_WORLD() => SEC_LEVEL_NONE,
 SEC_SCOPE_USER()  => SEC_LEVEL_NONE,
 SEC_SCOPE_GROUP() => {} 
};


my %LEVEL_VERBOSE = (
 SEC_LEVEL_NONE_VERBOSE()  => SEC_LEVEL_NONE,
 SEC_LEVEL_READ_VERBOSE()  => SEC_LEVEL_READ,
 SEC_LEVEL_WRITE_VERBOSE() => SEC_LEVEL_WRITE,
);

my %LEVEL_CODE = (
 SEC_LEVEL_NONE()          => SEC_LEVEL_NONE_VERBOSE,
 SEC_LEVEL_READ()          => SEC_LEVEL_READ_VERBOSE,
 SEC_LEVEL_WRITE()         => SEC_LEVEL_WRITE_VERBOSE,
);

my $INITIAL_SECURITY_DEFAULT = SEC_LEVEL_NONE;



# Returns: security level for a particular object/class given a scope
# and if necessary, a scope_id; should always return at least the
# security level for the WORLD scope, since everything must have at
# least a permission for the WORLD scope

sub check_security {
  my ( $class, $p ) = @_;
  my $sec_info = $p->{sec_info};
  unless ( $sec_info ) {
    _w( 1, "Retrieving security information." );
    $p->{user} = shift @{ $p->{user} }   if ( ref $p->{user} eq 'ARRAY' );
    
    # Retrieve security. If a subclass wants to implement a different
    # way of implementing security, this is the method to override.
    
    $sec_info = eval { $class->get_security( $p ) };
    if ( $@ ) {
      $SPOPS::Error::user_msg = 'Cannot retrieve security settings for checking';
      my $ei = SPOPS::Error->get;
      _w( 1, "Error found trying to retreive security settings: $@\n", 
             Dumper( SPOPS::Error->get ) );
      die $SPOPS::Error::user_msg;
    }
  }

  _w( 1, "Security information:\n", Dumper( $sec_info ) );
  
  # If a user security level exists, return it
  
  if ( my $user_level = $sec_info->{ SEC_SCOPE_USER() } ) {
    _w( 1, "Return level ($user_level) at scope USER." );
    return $user_level;
  }
  
  # Go through the groups; if there are groups, we return the highest
  # level among them.
  
  my $group_max = undef;
  foreach my $gid ( keys %{ $sec_info->{ SEC_SCOPE_GROUP() } } ) {
    my $group_level = $sec_info->{ SEC_SCOPE_GROUP() }->{ $gid } ;
    $group_max = ( $group_level > $group_max ) ? $group_level : $group_max;
    _w( 1, "Level of GROUP ($gid) is ($group_level)" );
  }
  return $group_max  if ( $group_max );
  
  my $world_level = $sec_info->{ SEC_SCOPE_WORLD() };
  _w( 1,  "Return level ($world_level) at scope WORLD" );
  return $world_level;
}

# Returns hashref

sub get_security {
  my ( $item, $p ) = @_;
  
  # Since we can pass in the class/oid, those take precedence
  
  my ( $class, $oid ) = $item->_get_object_info_for_security( $p->{class}, $p->{oid} );
  _w( 1, "Checking security for $class ($oid) with:\n", Dumper( $p ) );
  
  my ( $user, $group_list ) = $item->get_security_scopes( $p );
  
  if ( my $security_info = $item->_check_superuser( $user, $group_list ) ) {
    _w( 1, "Superuser is logged in, can do anything" );
    return $security_info;
  }
  
  my $sec_obj_class = $p->{security_object_class} || $item->global_security_object_class;
  _w( 1, "Using security object ($sec_obj_class)" );
  my $sec_listing = eval { $sec_obj_class->fetch_by_object( $class, { oid => $oid, user => $user,
                                                                      group => $group_list } ) };
  if ( $@ ) {
    $SPOPS::Error::user_msg = 'Cannot retrieve security listing';
    _w( 0, "Error retrieving security listing: $@" );
    die $SPOPS::Error::user_msg;
  }
  return $sec_listing || \%{ $EMPTY };
}

sub get_security_scopes {
  my ( $item, $p ) = @_;
  my $user       = undef;
  my $group_list = [];
  
  _w( 1, "Checking security scopes with:\n", Dumper( $p ) );

  # If both user and group(s) are passed in, we need to modify the
  # group list to include the groups that the user belongs to as well
  # as the groups specified
  
  if ( $p->{user} and $p->{group} ) {
    _w( 1, "Both user and group were specified." );
    $user       = $p->{user};
    $group_list = eval { $p->{user}->group; };   
    _w( 0, "Cannot fetch groups from user record: $@." ) if ( $@ );
    my @extra_group = ( ref $p->{group} eq 'ARRAY' ) ? @{ $p->{group} } : ( $p->{group} );
    push @{ $group_list }, @extra_group;
  }
  
  # The default (no user, no group) is just to get the user and its
  # groups
  
  elsif ( ! $p->{user} and ! $p->{group} ) {
    _w( 1, "Neither user/group specified, using logins." );
    $user       = $item->global_user_current;
    $group_list = $item->global_group_current;

    # If no user or group was passed in, and we cannot retrieve
   # a user object with the global_user_current call, then
   # all we want to get is the WORLD security level, which
   # means we can skip the user/group_list stuff altogether
   #
   # NOTE: even tho it doesn't appear, there IS a dependency between
   # the next two clauses; that is, you *MUST NOT* check to see if 
   # $user->{user_id} == 1 if there actually is no user. Otherwise
   # perl will autovivify a hashref in $R->{auth}->{user} which 
   # will throw a 800-pound monkey wrench into operations.
   # We really need to look into that, it's quite brittle.
    
    unless ( $user ) {
      _w( 1, "No user or groups found." );
      $user       = undef;
      $group_list = undef;
    }
  }
  
  # If we were given a user to check, base the group_list around the
  # groups the user belongs to
  
  elsif ( $p->{user} ) {
    _w( 1, "Only user specified; using user's groups." );
    $user       = $p->{user};
    $group_list = eval { $p->{user}->group; };
    _w( 0, "Cannot fetch groups from user record: $@." ) if ( $@ );
  }
  
  # Otherwise, the group list is based on whatever was passed in
  
  elsif ( $p->{group} ) {
    _w( 1, "Only group specified." );
    $group_list = ( ref $p->{group} eq 'ARRAY' ) ? $p->{group}: [ $p->{group} ];
  }
  return ( $user, $group_list );
}

sub set_security {
  my ( $item, $p ) = @_;
  my $sec_obj_class = $p->{security_object_class} || $item->global_security_object_class;
  
  # First ensure that both a level is specified...
  
  unless ( $p->{level} ) {
    my $msg = 'Set security failed';
    SPOPS::Error->set( { user_msg => $msg, type => 'security',
                         system_msg => 'No permissions scalar/hashref passed in.',
                         method => 'set_security' } );
    die $msg;
  }
  
  # ...and that a scope is specified
  
  unless ( $p->{scope} ) {
    my $msg = 'Set security failed';
    SPOPS::Error->set( { user_msg => $msg, type => 'security',
                         system_msg => 'No scope passed in.',
                         method => 'set_security' } );
    die $msg;
  }

  # Since we can pass in the class/oid, those take precedence
  
  my ( $class, $oid ) = $item->_get_object_info_for_security( $p->{class}, $p->{oid} );
  _w( 1, "Checking security for $class ($oid)" );
  
  # If we were passed a particular scope, just return
  # the results of updating that information
  
  unless ( ref $p->{scope} ) {
    if ( $p->{scope} eq SEC_SCOPE_WORLD ) {
      my $rv = eval {  $item->set_item_security( { class => $class, oid => $oid, level => $p->{level},
                                                   scope => $p->{scope}, scope_id => $p->{scope_id} } ) };
      if ( $@ ) {
        $SPOPS::Error::user_msg = 'Cannot set security';
        die $SPOPS::Error::user_msg;
      }
      return $rv;
    }
    
    # For user/group, we can pass in multiple items for which we want to
    # set security acting upon a particular class/object; the test for this
    # is if $p->{level} is a hashref.
    
    elsif ( $p->{scope} eq SEC_SCOPE_GROUP or $p->{scope} eq SEC_SCOPE_USER ) {
      if ( ref $p->{level} eq 'HASH' ) {
        my $rv = eval { $item->set_multiple_security( { class => $class, oid => $oid, level => $p->{level},
                                                        scope => $p->{scope} } ) };
        if ( $@ ) {
          $SPOPS::Error::user_msg = 'Cannot set security';
          die $SPOPS::Error::user_msg;
        }
        return $rv;
      }
      my $rv = eval { $item->set_item_security( { class => $class, oid => $oid, level => $p->{level},
                                                  scope => $p->{scope}, scope_id => $p->{scope_id} } ) };
      if ( $@ ) {
        $SPOPS::Error::user_msg = 'Cannot set security';
        die $SPOPS::Error::user_msg;
      }
      return $rv;
    }
    my $msg = 'Set security failed';
    SPOPS::Error->set( { user_msg => $msg, type => 'security',
                         system_msg => 'Unrecognized scope passed in',
                         extra => { scope => $p->{scope} } } );
    die $msg;
  }
  
  # If scope is a reference but not an arrayref, we have a problem
  
  if ( ref $p->{scope} ne 'ARRAY' ) {
    my $msg = 'Set security failed';
    SPOPS::Error->set( { user_msg => $msg, type => 'security',
                         system_msg => 'Unrecognized scope passed in',
                         extra => { scope => $p->{scope} } } );
    die $msg;
  }
  
  # If level is not a hashref (since we are using multiple scopes) 
  # at this point, we have a problem
  
  if ( ref $p->{level} ne 'HASH' ) {
    my $msg = 'Set security failed';
    SPOPS::Error->set( { user_msg => $msg, type => 'security',
                         system_msg => 'Multiple SCOPE arguments but param "level"  not a hashref.',
                         extra => { level => $p->{level} } } );
    die $msg;
  }
  
  # If we were passed multiple scope entries, go through each one
  # and total up the items changed for return. Note that we no
  # longer have a need for scope_id (for user/group) since that logic
  # is embedded within the level hashref
  
  # Note that *removing* security must be done outside this routine.
  # That is, you can't simply pass a full list of 'new' security
  # options for a particular object/class and expect this method to
  # sort them out for you
  
  my $total = scalar @{ $p->{scope} };
  my $count = 0;
  my @error_list;
  
 SCOPE:
  foreach my $scope ( @{ $p->{scope} } ) {
    if ( $scope eq SEC_SCOPE_WORLD ) {
      $count += eval { $item->set_item_security( { class => $class, $oid => $oid, scope => $scope, 
                                                   level => $p->{level}->{ $scope } } ); };
      if ( $@ ) { 
        push @error_list, $class->_assemble_error_message( scalar @error_list + 1 );
      }
    }
    elsif ( $scope eq SEC_SCOPE_GROUP or $scope eq SEC_SCOPE_USER ) {
      $count += eval { $item->set_multiple_security( { class => $class, oid => $oid, scope => $scope, 
                                                       level => $p->{level}->{ $scope } } ); };
      if ( $@ ) {
        push @error_list, $SPOPS::Error::system_msg;
      }
    }
    
    _w( 0, "Cannot set security for scope <$scope> since it is not a WORLD/USER/GROUP" );
  }
  if ( scalar @error_list ) {
    $SPOPS::Error::system_msg = join "\n\n", @error_list;
   die 'Set security failed for one or more items';
  }
  return 1;       
}

sub set_item_security {
  my ( $item, $p ) = @_;
  
  # Since we can pass in the class/oid, those take precedence
  
  my ( $class, $oid ) = $item->_get_object_info_for_security( $p->{class}, $p->{oid} );
  _w( 1, "Modifying scope $p->{scope} ($p->{scope_id}) for $class ($oid) with $p->{level}" );
  
  my $sec_obj_class = $p->{security_object_class} || $item->global_security_object_class;
  my $obj = eval { $sec_obj_class->fetch_match( $class, { oid => $oid, scope => $p->{scope}, 
                                                          scope_id => $p->{scope_id} } ); };
  if ( $@ ) { 
    _w(0, "Error found trying to match parametersto an existing object\n",
       "Error: ($@) $SPOPS::Error::system_msg" );
  }
  
  unless ( $obj ) {
    _w( 1, "Current object does not exist. Creating one." );
    $obj = $sec_obj_class->new( { class => $class, oid => $oid, 
                                  scope => $p->{scope}, scope_id => $p->{scope_id} } );
  }
  
  # if there is no change, we're done
  return 1 if ( $obj->{level} == $p->{level} );  
  $obj->{level} = $p->{level};
  
  # Let the error fall through

 return $obj->save;
}

sub set_multiple_security {
  my ( $item, $p ) = @_;

  # Since we can pass in the class/oid, those take precedence
  
  my ( $class, $oid ) = $item->_get_object_info_for_security( $p->{class}, $p->{oid} );
  _w( 1, "Setting multiple security for $class ($p->{oid}) and scope $p->{scope}." );
  
  my $sec_obj_class = $p->{security_object_class} || $item->global_security_object_class;
  
  # Remove any entries for superuser/admin
  
  delete $p->{level}->{1};
  
  # Count up the number of modifications we are making -- if there are 
  # none then we're done
  
  return 1 unless ( scalar keys %{ $p->{level} } );
  my @error_list = ();
  
 ITEM:
  foreach my $id ( keys %{ $p->{level} } ) {
    _w( 1, "Setting ID $id to $p->{level}->{$id}" );
    eval { $item->set_item_security({ class => $class, oid => $oid, 
                                      scope => $p->{scope}, scope_id => $id, 
                                      level => $p->{level}->{ $id } }) };
    if ( $@ ) { 
      push @error_list, $class->_assemble_error_message( scalar @error_list + 1 );
    }
  }
  
  if ( scalar @error_list ) {
    $SPOPS::Error::system_msg = join "\n\n", @error_list;
    die 'Set security failed for one or more items';
  }
  return 1;
}

sub remove_item_security {
  my ( $item, $p ) = @_;  
  if ( $p->{scope} ne SEC_SCOPE_WORLD and $p->{scope_id} == 1 ) {
    _w( 0, "Will not remove security with scope $p->{scope} ($p>{scope_id}) - admin." );
    return undef;
  }
  
  # Since we can pass in the class/oid, those take precedence
  
  my ( $class, $oid ) = $item->_get_object_info_for_security( $p->{class}, $p->{oid} );
  _w( 1, "Removing security for $class ($oid) with scope $p->{scope} ($p->{scope_id})" );
  
  my $sec_obj_class = $p->{security_object_class} || $item->global_security_object_class;
  my $obj = eval { $sec_obj_class->fetch_match( $class, { oid => $oid, scope => $p->{scope}, 
                                                          scope_id => $p->{scope_id} } ); };
  if ( $@ ) {
    _w( 0, "Error found trying to match parameters",
           " to an existing object\nError: $@->{error}\nSQL: $@->{sql}" );
  }
  unless ( $obj ) {
    _w( 0, "Security object does not exist with parameters, so we cannot remove it." );
    return undef;
  }
  
  # Let error trickle up
  
  my $rv = eval { $obj->remove };
  if ( $@ ) {
    $SPOPS::Error::user_msg = 'Cannot remove security setting for object';
    die $SPOPS::Error::user_msg;
  }
  return $rv;
}

sub _get_object_info_for_security {
  my ( $item, $class, $id ) = @_;
  $id ||= '0';
  return ( $class, $id )          if ( $class );
  return ( ref $item, $item->id ) if ( ref $item ); 
  return ( $item, $id );
}

# See if this is uid=1 or is a member of gid=1

sub _check_superuser {
  my ( $item, $user,  $group_list ) = @_;
  return undef unless ( $user or $group_list );
  my %allow_all = %{ $EMPTY }; 
  $allow_all{ SEC_SCOPE_USER() } = SEC_LEVEL_WRITE;
 
  if ( ref $user and $user->{user_id} == 1 ) {
    return \%allow_all;
  }
  if ( ref $group_list eq 'ARRAY' ) {
    foreach my $group ( @{ $group_list } ) {
      return \%allow_all if ( $group->{group_id} == 1 );
    }
  }
  return undef;
}

sub create_initial_security {
  my ( $item, $p ) = @_;

  # Since we can pass in the class/oid, those take precedence

  my ( $class, $oid ) = $item->_get_object_info_for_security( $item, $p->{class}, $p->{oid} );
  _w( 1, "Setting initial security for $class ($p->{oid})" );
  
  # \%init describes the initial security to create for this object;
  # note that \%init may describe code to execute or it may simply
  # describe a level to denote
  
  my $init = $class->creation_security;
  return undef unless ( ref $init and scalar keys %{ $init } );
  
  # Get the current user and groups
  
  my $user  = $class->global_user_current;
  my $group = $class->global_group_current;
  
  my @error_list = ();
  
  # \%level holds the actual security settings for this object
  
  my $level = {};
  
  # If our level assignment looks like this:
  # creation_security => {
  #  code => [ 'MyApp::SecurityPolicy' => 'handler' ] },
  # },
  # 
  # Then we execute "MyApp::SecurityPolicy->handler( \% ), passing the
  # parameters class and oid (for the object), $user (current user
  # object) and $group (arrayref of groups the user belongs to)
  # 
  
  # The code should return a hashref of either scope => SEC_LEVEL_* (in
  # the case of USER and WORLD) or scope => { scope_id => SEC_LEVEL* }
  # (in the case of GROUP). If an 'undef' is passed for a scope then
  # that scope will not be processed. For example:
  #
  # return { u => undef,
  #          g => { $main_gid => SEC_LEVEL_READ, $admin_gid => SEC_LEVEL_WRITE },
  #          w => SEC_LEVEL_NONE };
  
  if ( ref $init->{code} eq 'ARRAY' ) {
    my ( $pkg, $method ) = @{ $init->{code} };
    _w( 1, "$pkg\-\>$method being executed for security" );
    $level = eval { $pkg->$method( { class => $class, oid => $p->{oid},
                                     user => $user, group => $group } ); };
    if ( $@ ) {
      push @error_list, $class->_assemble_error_message( scalar @error_list + 1 );
      _w( 0, "ERROR trying to execute code: $@" );
    }
    _w( 1, "Result of code:\n", Dumper( $level ) );
  }
  
  # Go through each scope specified in the init and evaluate the
  # specification for initial security. 

  else {

   # Create a list of the group_id for ez-reference
    
    my @gid = map { $_->{group_id} } @{ $group };
    
  SCOPE:
    foreach my $scope ( keys %{ $init } ) {
      my $todo = $init->{ $scope };
      next unless ( $todo );
      _w( 1, "Determining security level for $scope" );
      
      # If our level assignment looks like this:
      # creation_security => {
      #  ...,
      #  g => { 3 => WRITE },
      #  ...,
      # },
      # 
      # Then we want to do the assignments for the IDs in that scope
      
      if ( ref $todo eq 'HASH' ) {
        $level->{ $scope } = { map { $_ => $LEVEL_VERBOSE{ uc $todo->{$_} } } 
                               keys %{ $todo } };
     }
     
     # Otherwise it will look like this:
     # creation_security => {
     #  ...,
     #  g => 'WRITE',
     #  ...,
     # },
     # 
     # Which means we'd want to apply WRITE for all the groups
     # this user belongs to. Be careful with this! (remember that 'public'
     # is a group, too).
      
      else {
        $level->{w} = $LEVEL_VERBOSE{ uc $todo }                        if ( $scope eq 'w' );
        $level->{u} = { $user->id() => $LEVEL_VERBOSE{ uc $todo } }     if ( $scope eq 'u' );
        $level->{g} = { map { $_ => $LEVEL_VERBOSE{ uc $todo } } @gid } if ( $scope eq 'g' );
      }
    }
    _w( 1, "Level assigned:\n", Dumper( $level ) );
  }
  
  # Now that \%level is all setup, process it

 # Ensure that this is a *$class* (this was the focus of bugs earlier,
 # exhibited by something in the sys_security table that looks like
 # "This::Class=HASH(0x8bb7028)"
  
  my $obj_class = ref $class || $class;
  
  # First do WORLD 
  
  $level->{w} ||= $INITIAL_SECURITY_DEFAULT;
  eval { $class->set_item_security( { class => $obj_class, oid => $p->{oid}, 
                                      level => $level->{w},
                                      scope => SEC_SCOPE_WORLD } ); };
  if ( $@ ) {
    push @error_list, $class->_assemble_error_message( scalar @error_list + 1 );
  }
  _w( 1, "Set initial security for WORLD to $level" );

  # Doing the user and group perms is identical, so we don't 
  # need to partition by scope for them 

  # Note that we're relying on the fact that u => SEC_SCOPE_USER and 
  # g  => SEC_SCOPE_GROUP; if this changes we'll have to do a little
  # mapping from the scopes in $level to the actual scope values
  
  foreach my $scope ( ( SEC_SCOPE_USER, SEC_SCOPE_GROUP ) ) {
    foreach my $id ( keys %{ $level->{ $scope } } ) {
      eval { $class->set_item_security( { class => $obj_class, oid => $p->{oid}, 
                                          level => $level->{ $scope }->{ $id },
                                          scope => $scope, scope_id => $id } ); };
      if ( $@ ) {
        push @error_list, $class->_assemble_error_message( scalar @error_list + 1 );
      }
      _w( 1, "Set initial security for $scope ($id) to $level->{$id}" );
    }
  }
  
  if ( scalar @error_list ) {
    $SPOPS::Error::system_msg = join "\n\n", @error_list;
    die 'Set initial security failed for one or more items';
  }
  return 1;
} 

sub _assemble_error_message {
  my ( $class, $count ) = @_;
  my $value_list = ( ref $SPOPS::Error::extra->{value} ) 
                      ? join( ' // ', @{ $SPOPS::Error::extra->{value} } )
                      : 'none reported';
  return qq(Error $count\n$@\n$SPOPS::Error::system_msg\n) .
         qq(SQL: $SPOPS::Error::extra->{sql}\nValues: $value_list);
}

1;

__END__

=pod

=head1 NAME

SPOPS::Secure - Implement security across one or more classes of SPOPS objects

=head1 SYNOPSIS

 package MySPOPS::Class;

 use SPOPS::Secure qw( :all ); # import the security constants

 @MySPOPS::Class::ISA = qw( SPOPS::Secure SPOPS::DBI );

=head1 DESCRIPTION

By adding this module into the @ISA variable for your 
SPOPS class, you implement a mostly transparent per-object 
security system. This security system relies on a few things
being implemented:

=over 4

=item *

A SPOPS class implementing users

=item *

A SPOPS class implementing groups

=item *

A SPOPS class implementing security objects

=back

Easy, eh? Fortunately, SPOPS comes with all three, although
you are free to modify them as you see fit.

=head2 Overview of Security

Security is implemented with a number of methods that are called
within the SPOPS implementation module. For instance, every time you
call I<fetch()> on an object, the system first determines whether you
have rights to do so. Similar callbacks are located in I<save()> and
I<remove()>. If you do not either define the method in your SPOPS
implementation or use this module, the action will always be allowed.

We use the Unix-style of permission scheme, separating the scope into:
USER, GROUP and WORLD from most- to least-specific. (This is
abbreviated as U/G/W.) When we check permissions, we check whether a
security level is defined for the most-specific item first, then work
our way up to the least_specific. (We use the term 'scope' frequently
in the module and documentation -- a 'specific scope' is a particular
user or group, or the world.)

Even though we use the U/G/W scheme from Unix, we are not constrained 
by its history. There is no strict 'ownership' assigned to an object
as there is to a Unix file. Instead, an object can have assigned to
it permissions from any number of users, and any number of groups.

There are three settings for any object combined with a specific scope:

 NONE:  The scope is barred from even seeing the object.
 READ:  The scope can read the object but not save it.
 WRITE: The scope can read, write and delete the object.

(To be explicit: WRITE permission implies READ permission as well; if
a scope has WRITE permission for an object, it can do anything with it,
including remove it.)

=head2 Security Rules

With security, there are some important assumptions. These
rules are laid out here.

=over 4

=item *

I<The most specific security wins.> This means that you might have set
permissions on an object to be SEC_LEVEL_WRITE for SEC_LEVEL_WORLD,
but if the user who is logged in has SEC_LEVEL_NONE, permission will
be denied.

=item *

I<All objects must have a WORLD permission.> Configuration for your
SPOPS object must include the I<initial_security> hash. The only
required field is 'WORLD', which defines the default WORLD permission
for newly-created objects. If you do not include this, the system will
automatically set the WORLD permission to SEC_LEVEL_NONE, which is
probably not what you want.

=back

For instance, look at an object that represents a news notice posted:

 Object Class: MyApp::News
 Object ID:    1625

 ------------------------------------------------
 | SCOPE | SCOPE_ID |  NONE  |  READ  |  WRITE  |
 ------------------------------------------------
 | USER  | 71827    |        |   X    |         |
 | USER  | 6351     |   X    |        |         |
 | USER  | 9182     |        |        |    X    |
 | GROUP | 762      |        |   X    |         |
 | GROUP | 938      |        |        |    X    |
 | WORLD |          |        |   X    |         |
 ------------------------------------------------

>From this, we can say:

=over 4

=item *

User 6351 can B<never> view this notice. Even though the user might be
a part of a group that can; even though WORLD has READ
permission. Since the user is explicitly forbidden from viewing the
notice, nothing else matters.

=item *

If a different User (say, 21092) who belongs to both Group 762 and
Group 938 tries to determine permission for this object, that User
will have WRITE permission since the system returns the highest
permission granted by all Group memberships.

=item *

Any user who is not specified here and who does not belong to either
Group 762 or Group 938 will get READ permission to the object,
reverting to the permission for the scope WORLD.

=back

=head2 Setting Security for Created Objects

The Unix paradigm of file permissions assumes several things.

=head2 User and Group Objects

It is a fundamental tenet of this persistence framework that 
it should have no idea what your application looks like. 
However, since we deal with user and group objects, it is 
necessary to enforce some standards.

=over 4

=item *

Must be able to retrieve the ID of the object with the method call
'id'. The ID value can be numeric or it can be a string, but it must
have 16 or fewer characters.

=item *

Must be able to get an arrayref of members. With a group object, you
must implement a method that returns users called 'user'. Similarly,
your user object must implement a method that returns the groups that
user belongs to via the method 'group':

 # Note that 'login_name' is not required as a 
 # parameter; this is just an example
 my $user_members = eval { $group->user };
 foreach my $user ( @{ $user_members } ) {
   print "Username is $user->{login_name}\n";
 }

 # Note that 'name' is not required as a 
 # parameter; this is just an example
 my $groups = eval { $user->group };
 foreach my $group ( @{ $groups } ) {
   print "Group name is $group->{name}\n";
 }

=item *

Must be able to retrieve the logged-in user (and, by the rule stated
above, the groups that user belongs to).  This is done via the
I<global_user_current> method call. The SPOPS object or other class
must be able to fulfill this method and return a user object.

=back

=head1 METHODS

The methods that this class implements can be used by any SPOPS
class. The variable $item below refers to the fact that you can either
do an object method call or a class method call. If you do a class
method call, you must pass in the ID of the object for which you want
to get or set security.

However, you may also implement security on the class level as
well. For instance, if your application uses classes to implement
modules within an application, you might wish to restrict the module
by security very similar to the security implemented for individual
objects. In this case, you would have a class name and no object ID
(oid) value.

To do so, simply make the class a subclass of SPOPS::Secure.  All the
methods remain exactly the same.

=head2 check_security( [ \%params ] )

The method get_security() returns a code corresponding to the LEVEL
constants exported from this package. This code tells you what
permissions the logged in user has. You can also pass user and group
parameters to check security for other items as well.

Note that you can check security for multiple groups but only one user
at a time. Passing an arrayref of user objects for the 'user'
parameter will result in the first user object being checked and the
remainder discarded. This is unlikely to be what you need.

Examples:

 # Find the permission for the currently logged-in user for $item
 $item->check_security();

 # Get the security for this $item for a particuar
 # user; note that this *does* find the groups this
 # user belongs to and checks those as well
 $item->check_security( user => $user );

 # Find the security for this item for either of the
 # groups specified
 $item->check_security( group => [ $group, $group ] );

=head2 get_security( [ \%params ] )

Returns a hashref of security information about the particular class
or object. The keys of the hashref are the constants, SEC_SCOPE_WORLD,
SEC_SCOPE_GROUP and SEC_SCOPE_USER. The value corresponding to the
SEC_SCOPE_WORLD key is simply the WORLD permission for the object or
class. Similarly, the value of SEC_SCOPE_USER is the permission for 
the user specified. The SEC_SCOPE_GROUP key has as its value
a hashref with the IDs of the group as keys. (Examples below)

Note that if the user specified does not have permissions
for the class/object, then its entry is blank.

The parameters correspond to check_security. The default is to
retrieve the security for the currently logged-in user and groups
(plus WORLD), but you can restrict the output if necessary.

Note that the WORLD key is B<always> set, no matter how much 
you restrict the user/groups.

Finally: this will not be on the test, since you will probably not
need to use this very often. The I<check_security()> and
I<set_security()> methods are likely the only interfaces you need with
security whether it be object or class-based. The I<get_security()>
method is used primarily for internal purposes, but you might also
need it if you are writing security administration tools.

Examples:

 # Return a hashref using the currently logged-in
 # user and the groups the user belongs to
 # 
 # Sample of what $perm looks like:
 # $perm = { 'u' => 4, 'w' => 1, 'g' => { 5162 => 4, 7182 => 8 } };
 # 
 # Which means that the user has a permission of SEC_LEVEL_READ,
 # the user belongs to two groups with IDs 5162 and 7182 which have
 # permissions of READ and WRITE, respectively, and the WORLD
 # permission is NONE.
 my $perm = $item->get_security(); 

 # Find the security for a particular user object and its groups
 my $perm = $item->get_security( user => $that_user );

 # Find the security for two groups, no user objects.
 my $perm = $item->get_security( group => [ $group1, $group2 ] );

=head2 get_security_scopes( \%params )

Called by B<get_security()> to determine which scopes to use to check
security on an object.

=head2 set_security( \%params )

The method set_security() returns a status as to whether the
permission has been set to what you requested.

The default is to operate on one item at a time, but you can
specify many items at once with the 'multiple' parameter.

Examples:

 # Set $item security for WORLD to READ

 my $wrv =  $item->set_security( scope => SEC_SCOPE_WORLD, 
                                 level => SEC_LEVEL_READ );
 unless ( $wrv ) {
   # error! security not set properly
 }

 # Set $item security for GROUP $group to WRITE

 my $grv =  $item->set_security( scope => SEC_SCOPE_GROUP,
                                 scope_id => $group->id,
                                 level => SEC_LEVEL_WRITE );
 unless ( $grv ) {
   # error! security not set properly
 }

 # Set $item security for USER objects whose IDs are the keys in the
 # hash %multiple and whose values are the levels corresponding to the
 # ID.
 #
 # (Note that this is a contrived example for setting up the %multiple
 # hash - you should always do some sort of validation/checking before
 # passing user-specified information to a method.)

 my %multiple = (
  $user1->id => $cgi->param( 'level_' . $user1->id ),
  $user2->id => $cgi->param( 'level_' . $user2->id ) 
 );
 my $rv = $item->set_security( scope => SEC_SCOPE_USER,
                               level => \%multiple );
 if ( $rv != scalar( keys %multiple ) ) {
   # error! security not set properly for all items
 }

 # Set $item security for multiple scopes whose values
 # are in the hash %multiple; note that the hash %multiple
 # has a separate layer now since we're specifying multiple
 # scopes within it.

 my %multiple = (
  SEC_SCOPE_USER() => {
     $user1->id => $cgi->param( 'level_' . $user1->id ),
     $user2->id => $cgi->param( 'level_' . $user2->id ),
  },
  SEC_SCOPE_GROUP() => {
     $group1->id  => $cgi->param( 'level_group_' . $group1->id ),
  },
 );
 my $rv = $item->set_security( scope => [ SEC_SCOPE_USER, SEC_SCOPE_GROUP ],
                               level => \%multiple );

=head2 create_initial_security( \%params )

Creates the initial security for an object. This can be simple, or
this can be complicated :) It is designed to be flexible enough for us
to easily plug-in security policy modules whenever we write them, but
simple enough to be used just from the object configuration.

Object security configuration information is specified in the
'creation_security' hashref in the object configuration. A typical
setup might look like:

  creation_security => {
     u   => undef,
     g   => { level => { 3 => 'WRITE' } },
     w   => { level => 'READ'},
  },

Each of the keys maps to a (hopefully intuitive) scope: 

 u = SEC_SCOPE_USER
 g = SEC_SCOPE_GROUP
 w = SEC_SCOPE_WORLD

For each scope you can either name security specifically or you can
defer the decision-making process to a subroutine. The former is
called 'exact specification' and the latter 'code specification'. Both
are described below.

Note that the 'level' values used ('WRITE' or 'READ' above) do not
match up to the SEC_LEVEL_* values exported from this module. Instead
they are just handy mnemonics to use -- just lop off the 'SEC_LEVEL_'
from the exported variable:

 SEC_LEVEL_NONE  = 'NONE'
 SEC_LEVEL_READ  = 'READ'
 SEC_LEVEL_WRITE = 'WRITE'

B<Exact specification>

'Exact specification' does exactly that -- you specify the ID and
security level of the users and/or groups, along with one for the
'world' scope if you like. This is handy for smaller sites where you
might have a small number of groups.

The exact format is:

 SCOPE => { level => { ID => LEVEL,
                       ID => LEVEL, ... } }

Where 'SCOPE' is 'u' or 'g', 'ID' is the ID of the group/user and
'LEVEL' is the level you want to assign to that group/user. So using
our example above:

     g   => { level => { 3 => 'WRITE' } },

We assign the security level 'SEC_LEVEL_WRITE' to the group with ID 3.

You can also use shortcuts.

For the SEC_SCOPE_USER scope, if you specify a level:

    u    => { level => 'READ' }

Then that security level is assigned for the user who created the object.

For the SEC_SCOPE_GROUP scope, if you specify a level:

    g    => { level => 'READ' }

Then that security level is assigned for all of the groups to which
the user who created the object belongs.

If you specify anything other than a level for the SEC_SCOPE_WORLD
scope, the system will discard the entry.

B<Code specificiation>

You can also assign the entire process off to a separate routine:

  creation_security => {
     code => [ 'My::Package' => 'security_set' ]
  },

This code should return a hashref formatted like this

 { 
   u => SEC_LEVEL_*,
   g => { gid => SEC_LEVEL_* },
   w => SEC_LEVEL_*
 }

If you do not include a scope in the hashref, no security information
for that scope will be entered.

Parameters:

 class
   Specify the class you want to use to create the initial security.

 oid
   Specify the object ID you want to use to create the initial
   security.

=head1 TAGS FOR SCOPE/LEVEL

This module exports nothing by default. You can import specific tags
that refer to the scope and level, or you can import groups of them.

Note that you should B<always> use these tags. They may seem
unwieldly, but they make your program easier to read and allow us to
modify the values for these behind the scenes without you modifying
any of your code. If you use the values directly, you will get what is
coming to you.

You can import individual tags like this:

 use SPOPS::Secure qw( SEC_SCOPE_WORLD );

Or you can import the tags in groups like this:

 use SPOPS::Secure qw( :scope );

B<Scope Tags>

=over 4

=item *

SEC_SCOPE_WORLD

=item *

SEC_SCOPE_GROUP

=item *

SEC_SCOPE_USER

=back

B<Level Tags>

=over 4

=item *

SEC_LEVEL_NONE

=item *

SEC_LEVEL_READ

=item *

SEC_LEVEL_WRITE

=back

B<Verbose Level Tags>

These tags return a text value for the different security levels.

=over 4

=item *

SEC_LEVEL_VERBOSE_NONE (returns 'NONE')

=item *

SEC_LEVEL_VERBOSE_READ (returns 'READ')

=item *

SEC_LEVEL_VERBOSE_WRITE (returns 'WRITE')

=back

B<Groups of Tags>

=over 4

=item *

scope: brings in all SEC_SCOPE tags

=item *

level: brings in all SEC_LEVEL tags

=item *

verbose: brings in all SEC_LEVEL_*_VERBOSE tags

=item *

all: brings in all tags

=back

=head1 TO DO

B<Sort out the different set_* methods>

The different set_* methods are currently quite confusing.

B<Add SUMMARY level>

Think about adding a SUMMARY level of security. This would allow, for
instance, search results to bring up an object and display a title and
perhaps more (controlled by the object), but forbid actually viewing
the entire object.

B<Add caching>

Gotta gotta gotta get a caching interface done, where we simply say: 

 $object->cache_security_level( $user );

And cache the security level for that object for that user. **Any**
security modifications to that object wipe out the cache for that
object.

=head1 BUGS

=head1 COPYRIGHT

Copyright (c) 2001 intes.net, inc.. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHORS

Chris Winters  <chris@cwinters.com>

=cut