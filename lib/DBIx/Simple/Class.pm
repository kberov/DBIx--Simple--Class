package DBIx::Simple::Class;

use 5.01000;
use strict;
use warnings;
use DBIx::Simple;
use SQL::Abstract;
use Params::Check;
use Carp;

our $VERSION = '0.02';
$Params::Check::WARNINGS_FATAL = 1;
$Params::Check::CALLER_DEPTH   = $Params::Check::CALLER_DEPTH + 1;

#CONSTANTS

my $DEBUG = 0;
sub DEBUG { defined $_[1] ? ($DEBUG = $_[1]) : $DEBUG }

#tablename
sub TABLE {
  croak("You must define a tablename for your class: sub TABLE {'tablename'}");
}

#table columns
sub COLUMNS {
  croak("You must define fields for your class: sub COLUMNS {['id','name','etc']}");
}

#used to validate params to field-setters
my $_CHECKS = {};

sub CHECKS {
  croak("You must define your CHECKS subroutine that returns your private \$_CHECKS");
}

#default where
sub WHERE { {} }

my $DBIX;    #DBIx::Simple instance

#ATTRIBUTES
sub dbix {
  return ($DBIX ||= $_[1]) || croak('DBIx::Simple is not instantiated');
}

#METHODS

sub new {
  my ($class, $fields) = _get_obj_args(@_);
  $fields = Params::Check::check($class->CHECKS, $fields)
    || croak(Params::Check::last_error());
  my $self = {};
  bless $self, $class;
  $class->_make_field_attrs();
  $self->data($fields);
  return $self;
}

sub _make_field_attrs {
  my $class = shift;
  (!ref $class)
    || croak('Call this method as __PACKAGE__->make_field_attrs()');
  my $code = '';
  foreach my $column (@{$class->COLUMNS()}) {
    next if $class->can($column);    #careful: no redefine
    $code = "use strict;$/use warnings;$/use utf8;$/" unless $code;

    #Carp::carp('Making sub ' . $column) if $DEBUG;
    $code .= <<"SUB";
sub $class\::$column {
  my (\$self,\$value) = \@_;
  if(defined \$value){ #setting value
    \$self->{data}{$column} = \$self->_check($column=>\$value);
    #make it chainable
    return \$self;
  }
  \$self->{data}{$column}
    //= \$self->CHECKS->{$column}{default}; #getting value
}

SUB

  }
  $code .= "$/1;";

  #I know what I am doing. I think so... warn $code if $code;
  if (!eval $code) {    ##no critic (BuiltinFunctions::ProhibitStringyEval)
    croak($class . " compiler error: $/$code$/$@$/");
  }
  if ($DEBUG) {
    carp($class . " generated accessors: $/$code$/$@$/");
  }
  return;
}

#conveninece for getting key/vaule arguments
sub _get_args {
  return ref($_[0]) ? shift() : (@_ % 2) ? shift() : {@_};
}
sub _get_obj_args { return (shift, _get_args(@_)); }

sub _check {
  my ($self, $key, $value) = @_;
  my $args_out =
    Params::Check::check({$key => $self->CHECKS->{$key} || {}}, {$key => $value});
  return $args_out->{$key};
}

#fieldvalues HASHREF
sub data {
  my ($self, $args) = _get_obj_args(@_);
  if (ref $args && keys %$args) {
    for my $field (keys %$args) {
      unless (grep { $field eq $_ } @{$self->COLUMNS()}) {
        Carp::cluck(
          "There is not such field $field in table " . $self->TABLE . '! Skipping...')
          if $DEBUG;
        next;
      }
      $self->$field($args->{$field});
    }
  }

  #a key
  elsif ($args && (!ref $args)) {
    return $self->$args;
  }

  #they want all that we touched in $self->{data}
  return $self->{data};
}

1;

__END__

=encoding utf8

=head1 NAME

DBIx::Simple::Class - Advanced object construction for DBIx::Simple!

=head1 DESCRIPTION

This module is writen to replace the base model class in the MYDLjE project 
on github, but can be used independently as well. 

The class provides some useful methods which simplify representing rows from 
tables as Perl objects. It is not intended to be a full featured ORM at all. 
It is rather a DBA (Database Abstraction Layer). It simply saves you from 
writing the same SQl over and over again to construct well known objects 
stored in tables' rows. If you have to do complicated  SQL queries use directly 
L<DBIx::Simple/query> method. Use this base class if you want to construct Perl 
objects which store their data in table rows. 
That's it.

=head1 SYNOPSIS

  
  #1. In your class representing a template for a row in a database table or view
  package My::Model::AdminUser;
  use base DBIx::Simple::Class;

  #sql to be used as table
  sub TABLE { 'users' }
  sub WHERE { {group_id => 1 } }#admin group
  
  sub COLUMNS {[qw(id group_id login_name login_password first_name last_name)]}

  #used to validate params to field-setters
  my $_CHECKS = {
    id => { allow => qr/^\d+$/x },
    group_id => { allow => qr/^\d+$/x },
    login_name => {required => 1, allow => qr/^\p{IsAlnum}{4,12}$/x},
    #...
  };
  sub CHECKS{$_CHECKS}
  1;#end of My::Model::AdminUser

  #2. in as startup script or subroutine  
  DBIx::Simple::Class->dbix( DBIx::Simple->connect(...) );

  #3. usage 
  use My::Model::AdminUser;
  my $user = My::Model::AdminUser->select(login_name => 'fred')
  $user->first_name('Fred')->last_name('Flintstone');
  $user->save;
  #....
  my $user = My::Model::AdminUser->new(
    login_name => 'fred',
    first_name => 'Fred',
    last_name =>'Flintstone'
  );
  $user->save();
  print "new user has id:".$user->id;
  #...
  my @admins = $dbix->select(
    My::Model::AdminUser->TABLE,
    My::Model::AdminUser->COLUMNS,
    My::Model::AdminUser->WHERE
  )->objects(My::Model::AdminUser);



=head1 CONSTANTS

=head2 DEBUG

Flag to enable debug warnings.

    DBIx::Simple::Class->DEBUG(1);

=head2 TABLE

You B<must> define it in your subclass. This is the table where 
your object will store its data. Must return a string - the table name. 
It is used  internally in L<select> when retreiving a row from the database 
and when saving object data.

  sub TABLE { 'users' }
  # in select()
  $self->data($self->dbix->select(TABLE, COLUMNS, WHERE)->hash);

=head2 WHERE

A HASHREF suiatble for passing to an SQL::Abstract instance.
Default C<WHERE> clause for your class which will be appended to C<where> 
arguments for the L</select> method. Empty "C<{}>" by default.
This constant is optional.

  #package My::PublishedNote;
  sub WHERE { {data_type => 'note',published=>1 } };
  
                                                      
=head2 COLUMNS

You B<must> define it in your subclass. 
It must return an ARRAYREF with table columns to which the data is written.
It is used  internally in L</select> when retreiving a row from the database 
and when saving object data.

  sub COLUMNS { [qw(id cid user_id tstamp sessiondata)] };
  # in select()
  $self->data(
    $self->dbix->select(TABLE, COLUMNS, WHERE)->hash);

=head2 CHECKS

You B<must> define this soubroutine in your class and put in it your
C<$_CHECKS>. That's all.

  sub CHECKS{$_CHECKS}

=head1 ATTRIBUTES

=head2 dbix

This is an L<DBIx::Simple> instance and (as you guessed) provides direct access
to the current DBIx::Simple instance with L<SQL::Abstract> support.


=head1 METHODS

=head2 new

The constructor.  
Generates getters and setters (if needed) for the fields described in 
L</COLUMNS>. Sets the passed parameters as fields if they exists 
as column names.

  #Restore user object from sessiondata
  if($self->sessiondata->{user_data}){
    $self->user(MYDLjE::M::User->new($self->sessiondata->{user_data}));
  }

=head2 new_from_dbix_simple

A constructor called in L<DBIx::Simple/object> and 
<DBIx::Simple/objects>. Basically makes the same as above without 
checking the validity of the field values.


=head2 select

Instantiates an object from a saved in the database row by constructing 
and executing an SQL query based on the parameters. 
These parameters are used to construct the C<WHERE> clause for the 
SQL C<SELECT> statement. The API is the same as for 
L<DBIx::Simple/select> or L<SQL::Abstract/select> which is used 
internally. Prepends the L</WHERE> clause defined by you to 
the parameters. If a row is found puts it in L</data>. 
Returns C<$self>.

  my $user = MYDLjE::M::User->select(id => $user_id);

=head2 data

Common getter/setter for all L</COLUMNS>. 
Uses internally the specific field getter/setter for each field.
Returns a HASHREF - name/value pairs of the fields.

  $self->data(title=>'My Title', description =>'This is a great story.');
  my $fields = $self->data;
  $self->data($self->dbix->select(TABLE, COLUMNS, $where)->hash);

=head2 save

DWIM saver. If the object is fresh ( C<if (!$self-E<gt>id)> ) prepares and executes an C<INSERT> statment, otherwise preforms an C<UPDATE>. L</TABLE> is used to construct the SQL.

=head1 AUTHOR

Красимир Беров, C<< <berov at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to https://github.com/kberov/DBIx--Simple--Class/issues. 
I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc DBIx::Simple::Class


You can also look for information at:

=over 4

=item * The project wiki

L<https://github.com/kberov/DBIx--Simple--Class/wiki>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/DBIx-Simple-Class>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/DBIx-Simple-Class>

=item * Search CPAN

L<http://search.cpan.org/dist/DBIx-Simple-Class/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 SEE ALSO

L<DBIx::Simple>, <SQL::Abstract>, L<Params::Check>
L<https://github.com/kberov/MYDLjE>


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Красимир Беров.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
