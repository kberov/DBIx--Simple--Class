package DBIx::Simple::Class;

use 5.010;
use strict;
use warnings;
use DBIx::Simple;
use Params::Check;
use List::Util qw(first);
use Carp;

our $VERSION = '0.56';
$Params::Check::WARNINGS_FATAL = 1;
$Params::Check::CALLER_DEPTH   = $Params::Check::CALLER_DEPTH + 1;
my $_attributes_made = {};

#CONSTANTS

my $DEBUG = 0;
sub DEBUG { defined $_[1] ? ($DEBUG = $_[1]) : $DEBUG }

#tablename
sub TABLE {
  croak("You must define a table-name for your class: sub TABLE {'tablename'}!");
}

#table columns
sub COLUMNS {
  croak("You must define fields for your class: sub COLUMNS {['id','name','etc']}!");
}

#used to validate params to field-setters
my $_CHECKS = {};

sub CHECKS {
  croak(
    "You must define your CHECKS subroutine that returns your private \$_CHECKS HASHREF!"
  );
}

#default where
sub WHERE { {} }

sub PRIMARY_KEY {'id'}

sub ALIASES { {} }

my $SQL_CACHE = {};
my $SQL       = {};
$SQL = {
  SELECT => sub {
    my $class = shift;
    return $SQL_CACHE->{$class}{SELECT} ||= do {
      my $where = $class->WHERE;
      'SELECT ' 
        . join(',', @{$class->COLUMNS}) 
        . ' FROM ' 
        . $class->TABLE
        . (
        (keys %$where)
        ? ' WHERE '
          . join(' AND ',
          map { "$_=" . $class->dbix->dbh->quote($where->{$_}) }
            keys %$where)
        : ''
        );
      }
  },
  INSERT => sub {
    my $class = $_[0];

    #cache this query and return it
    return $SQL_CACHE->{$class}{INSERT} ||= do {
      my ($pk, $table, @columns) =
        ($class->PRIMARY_KEY, $class->TABLE, @{$class->COLUMNS});

      #return of the do
      "INSERT INTO $table ("
        . join(',', @columns)
        . ') VALUES('
        . join(',', map {'?'} @columns) . ')';
    };
  },
  UPDATE => sub {
    my $class = $_[0];

    #cache this query and return it
    return $SQL_CACHE->{$class}{UPDATE} ||= do {
      my $pk = $class->PRIMARY_KEY;

      #do we always update all columns?!?! Yes, if we always retreive all columns.
      my $SET = join(', ', map {qq($/$_=?)} @{$class->COLUMNS});
      'UPDATE ' . $class->TABLE . " SET $SET WHERE $pk=%s";
      }
  },
  SELECT_BY_PK => sub {
    my $class = $_[0];

    #cache this query and return it
    return $SQL_CACHE->{$class}{SELECT_BY_PK} ||= do {
      'SELECT '
        . join(',', @{$class->COLUMNS})
        . ' FROM '
        . $class->TABLE
        . ' WHERE '
        . $class->PRIMARY_KEY . '=?';
    };
  },
};

sub SQL {
  my ($class, $args) = _get_obj_args(@_);    #class
  croak('This is a class method. Do not use as object method.') if ref $class;

  if (ref $args) {                           #adding new SQL strings($k=>$v pairs)
    return $SQL->{$class} = {%{$SQL->{$class} || $SQL}, %$args};
  }

  #a key
  if (!ref $args) {

    #allow subclasses to override parent sqls and cache produced SQL
    my $_SQL =
         $SQL_CACHE->{$class}{$args}
      || $SQL->{$class}{$args}
      || $SQL->{$args}
      || $args;
    if (ref $_SQL) {
      return $_SQL->($class);
    }
    else {
      return $_SQL;
    }
  }

  #they want all
  return $SQL;
}


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
  $class->_make_field_attrs()
    unless $_attributes_made->{$class};
  return bless {data => $fields}, $class;
}

sub new_from_dbix_simple {
  $_[0]->_make_field_attrs() unless $_attributes_made->{$_[0]};
  return bless {

    #$_[1]->hash
    data =>
      $_[1]->{st}->{sth}->fetchrow_hashref($_[1]->{lc_columns} ? 'NAME_lc' : 'NAME'),
    new_from_dbix_simple => 1
    },
    $_[0];
}

sub select {
  my ($class, $where) = _get_obj_args(@_);
  return $class->dbix->select($class->TABLE, $class->COLUMNS,
    {%{$class->WHERE}, %$where})->object($class);
}

sub query {
  my $class = shift;
  return $class->dbix->query(@_)->object($class);
}

sub select_by_pk {
  my $class = shift;
  return $class->dbix->query($SQL_CACHE->{$class}{SELECT_BY_PK}
      || $class->SQL('SELECT_BY_PK'), shift)->object($class);
}

sub _make_field_attrs {
  my $class = shift;
  (!ref $class)
    || croak("Call this method as $class->make_field_attrs()");
  my $code = '';
  foreach (@{$class->COLUMNS}) {
    my $alias = $class->ALIASES->{$_} || $_;
    croak("You can not use '$alias' as a column name since it is already defined in "
        . __PACKAGE__
        . '. Please define an \'alias\' for the column to be used as method.')
      if __PACKAGE__->can($alias);
    next if $class->can($alias);    #careful: no redefine
    $code = "use strict;$/use warnings;$/use utf8;$/" unless $code;
    $code .= <<"SUB";
sub $class\::$alias {
  my (\$self,\$value) = \@_;
  if(defined \$value){ #setting value
    \$self->{data}{$_} = \$self->_check($_=>\$value);
    #make it chainable
    return \$self;
  }
  \$self->{data}{$_}
    //= \$self->CHECKS->{$_}{default}; #getting value
}

SUB

  }
  $code .= "$/1;";

  #I know what I am doing. I think so...
  unless (eval $code) {    ##no critic (BuiltinFunctions::ProhibitStringyEval)
    croak($class . " compiler error: $/$code$/$@$/");
  }
  if ($DEBUG) {
    carp($class . " generated accessors: $/$code$/$@$/");
  }
  return $_attributes_made->{$class} = 1;
}

#for outside modification during tests
sub _attributes_made {$_attributes_made}
sub _SQL_CACHE       {$SQL_CACHE}

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
      my $alias = $self->ALIASES->{$field} || $field;
      unless (first { $field eq $_ } @{$self->COLUMNS()}) {
        Carp::cluck(
          "There is not such field $field in table " . $self->TABLE . '! Skipping...')
          if $DEBUG;
        next;
      }

      #we may have getters/setters written by the author of the subclass
      # so call each setter separately
      $self->$alias($args->{$field});
    }
  }

  #a key
  elsif ($args && (!ref $args)) {
    my $alias = $self->ALIASES->{$args} || $args;
    return $self->$alias;
  }

  #they want all that we touched in $self->{data}
  return $self->{data};
}

sub save {
  my ($self, $data) = _get_obj_args(@_);

  #allow data to be passed directly and overwrite current data
  if (keys %$data) { $self->data($data); }
  local $Carp::MaxArgLen = 0;
  if (!$self->{new_from_dbix_simple}) {
    return $self->{new_from_dbix_simple} = $self->insert();
  }
  else {
    return $self->update();
  }
  return;
}

sub update {
  my ($self) = @_;
  my $pk = $self->PRIMARY_KEY;
  $self->{data}{$pk} || croak('Please define primary key column (\$self->$pk(?))!');
  $self->{SQL_UPDATE} ||= do {
    my $SET = join(', ', map { $_ . '=? ' } keys %{$self->{data}});
    'UPDATE ' . $self->TABLE . " SET $SET WHERE $pk=?";
  };
  return eval {
    $self->dbix->{dbh}->prepare_cached($self->{SQL_UPDATE})
      ->execute(values %{$self->{data}}, $self->{data}{$pk});
  } || croak($@ =~ s/ at \S+ line \d+\.\n\z//);

  #return $self->dbix->query($SQL, (map { $self->{data}{$_} } @columns));
}

sub insert {
  my ($self) = @_;
  my ($pk, $class) = ($self->PRIMARY_KEY, ref $self);
  eval {
    $self->dbix->{dbh}->prepare($SQL_CACHE->{$class}{INSERT} || $class->SQL('INSERT'))
      ->execute(map { $self->{data}{$_} } @{$self->COLUMNS});
  } || croak($@ =~ s/ at \S+ line \d+\.\n\z//);

  return $self->{data}{$pk} =
    $self->dbix->{dbh}->last_insert_id(undef, undef, $self->TABLE, $pk);

}

1;


# put a comment before __END__ marker so you can generate/use
# additional perl tags using exuberant ctags.
# example ctags filters to put in your ~/.ctags file:
#--regex-perl=/^\s*?use\s+(\w+[\w\:]*?\w*?)/\1/u,use,uses/
#--regex-perl=/^\s*?require\s+(\w+[\w\:]*?\w*?)/\1/r,require,requires/
#--regex-perl=/^\s*?has\s+['"]?(\w+)['"]?/\1/a,attribute,attributes/
#--regex-perl=/^\s*?\*(\w+)\s*?=/\1/a,aliase,aliases/
#--regex-perl=/->helper\(\s?['"]?(\w+)['"]?/\1/h,helper,helpers/
#--regex-perl=/^\s*?our\s*?[\$@%](\w+)/\1/o,our,ours/
#--regex-perl=/^=head1\s+(.+)/\1/p,pod,Plain Old Documentation/
#--regex-perl=/^=head2\s+(.+)/-- \1/p,pod,Plain Old Documentation/
#--regex-perl=/^=head[3-5]\s+(.+)/---- \1/p,pod,Plain Old Documentation/

#__END__

=encoding utf8

=head1 NAME

DBIx::Simple::Class - Advanced object construction for DBIx::Simple!

=head1 DESCRIPTION

This module is written to replace most of the abstraction stuff from the base 
model class in the MYDLjE project on github, but can be used independently as well. 

The class provides useful methods which simplify representing rows from 
tables as Perl objects and modifying them. It is not intended to be a full 
featured ORM. It does not support relational mapping. 
This is left to the developers using this class.

DBIx::Simple::Class is a database table/row abstraction. 
At the same time it is not just a fancy representation of a table row 
like DBIx::Simple::Result::RowObject. 
Usin this module will make your code more organized, clean and reliable
(separation of concerns + field-validation). 
You will even get some more performance over plain DBIx::Simple.
Last but not least, this module has no other non-CORE dependencies besides DBIx::Simple.
See below for details.

=head1 SYNOPSIS

  
  #1. In your class representing a template for a row in a database table or view
  package My::Model::AdminUser;
  use base qw(DBIx::Simple::Class);

  #sql to be used as table
  sub TABLE { 'users' }  #or: use constant TABLE =>'users';
  
  sub COLUMNS {[qw(id group_id login_name login_password first_name last_name)]}

  #used to validate params to field-setters
  sub CHECKS{{
    id => { allow => qr/^\d+$/x },
    group_id => { allow => qr/^1$/x, default=>1 },#admin group_id
    login_name => {required => 1, allow => qr/^\p{IsAlnum}{4,12}$/x},
    #...
  }}
  
  sub WHERE { group_id=> 1} #select only users from admin group
  
  1;#end of My::Model::AdminUser

  #2. In a start-up script or subroutine
  DBIx::Simple::Class->dbix( DBIx::Simple->connect(...) );

  #3. usage 
  use My::Model::AdminUser;
  my $user = $dbix->select(
    My::Model::AdminUser->TABLE, '*', {login_name => 'fred'}
  )->object('My::Model::AdminUser')
  
  #or better (if SQL::Abstract is installed)
  my $user = My::Model::AdminUser->select(login_name => 'fred'); #this is cleaner
  
  $user->first_name('Fred')->last_name('Flintstone'); #chainable setters
  $user->save; #update row
  #....
  my $user = My::Model::AdminUser->new(
    login_name => 'fred',
    first_name => 'Fred',
    last_name =>'Flintstone'
  );
  $user->save();#insert new user
  print "new user has id:".$user->id;
  #...
  #select many
  my $class = 'My::Model::AdminUser';
  my @admins = $dbix->select(
    $class->TABLE,
    $class->COLUMNS,
    $class->WHERE
  )->objects($class);
  #or
  my @admins = $dbix->query(
    $VERY_COMPLEX_SQL, @bind_variables
  )->objects($class);


=head1 CONSTANTS

=head2 TABLE

You B<must> define it in your subclass. This is the table where 
your object will store its data. Must return a string - the table name. 
And with little imagination you could put here some complex SQL or 
an already prepared view: 

  (SELECT * FROM users WHERE column1='something' column2='other')

It is used  internally in L</select> L</update> and L</insert> when saving object data.

  sub TABLE { 'users' }
  #using DBIx::Simple select() or query()
  dbix->select($class->TABLE, $class->COLUMNS, {%{$class->WHERE}, %$where})->object($class);

=head2 WHERE

A HASHREF suitable for passing to L<DBIx::Simple/select>. 
It is also used  internally in L</select>.
Default C<WHERE> clause for your class. Empty "C<{}>" by default.
This constant is optional.

  package My::PublishedNote;
  sub WHERE { {data_type => 'note',published=>1 } };
  #...
  use My::PublishedNote;
  #somewhere in your application
  my $note = My::PublishedNote->select(id=>12345);
                                                      
=head2 COLUMNS

You B<must> define it in your subclass. 
It must return an ARRAY-REF with table columns to which the data is written.
It is used  in L<DBIx::Simple/select> when retrieving a row from the database 
and when saving object data. This list is also used to generate specific 
getters and setters for each data-field.

  sub COLUMNS { [qw(id cid user_id tstamp sessiondata)] };
  # in select()
  dbix->select($class->TABLE, $class->COLUMNS, {%{$class->WHERE}, %$where})->object($class);

In case you have table columns that collide with some of the methods defined in this class like L</data>,
L</save> etc., you can define aliases that will be used as method names. 
See L</ALIASES>.

=head2 CHECKS

You B<must> define this subroutine/constant in your class and put in it your
C<$_CHECKS>. 
C<$_CHECKS> is a HASHREF that must conform to the syntax supported by L<Params::Check/Template>.

  sub CHECKS{$_CHECKS}

=head2 PRIMARY_KEY

The column that will be used to uniquely recognise your object from others 
in the same table. Default: 'id'.

    use constant PRIMARY_KEY => 'product_id';
    #or simply
    sub PRIMARY_KEY {'product_id'}

=head2 ALIASES

In case you have table columns that collide with some of the package methods like L</data>,
L</save> etc., you can define aliases that will be used as method names. 

You are free to define your own getters/setter for fields. They will not be overridden. 
All they need to do is to check the validity of the input and put the changed value in 
C<$self-E<gt>{data}>.

  #in you class
  package My::Collision;
  use base qw(DBIx::Simple::Class);

  use constant TABLE   => 'collision';
  use constant COLUMNS => [qw(id data)];
  use constant WHERE   => {};
  use constant ALIASES => {data => 'column_data'};

  #CHECKS are on columns
  use constant CHECKS => {
    id   => {allow   => qr/^\d+$/x},
    data => {default => '',}           #that's ok
  };
  1;
  #usage
  my $coll = My::Collision->new(data => 'some text');
  #or
  my $coll = My::Collision->query('select * from collision where id=1');
  $coll->column_data('changed')->save;
  #or
  $coll->data(data=>'changed')->save;
  #...
  $coll->column_data; #returns 'changed'

=head1 ATTRIBUTES

=head2 dbix

This is a class attribute, shared among all subclasses of DBIx::Simple::Class. 
This is an L<DBIx::Simple> instance and (as you guessed) provides direct access
to the current DBIx::Simple instance (with L<SQL::Abstract> support eventually :)).

  DBIx::Simple::Class->dbix( DBIx::Simple->connect(...) );
  #later in My::Note
  $self->dbix->query(...);#same instance
  #or
  __PACKAGE__->dbix->query(...);#same instance
  dbix->query(...);#same instance

=head2 DEBUG

Flag to enable/disable debug warnings. Influences all DBIx::Simple::Class subclasses.

    DBIx::Simple::Class->DEBUG(1);
    my $note = My::Note->new;# see in the log what methods are generated for your columns
    DBIx::Simple::Class->DEBUG(0);

=head1 METHODS

=head2 new

Constructor.  
Accessors listed in COLUMNS are generated on first call for the fields described in 
L</COLUMNS>. On any subsequent call field-accessors are not generated. 
Accepts named parameters or a HASHREF containing named parameters.
Sets the passed parameters as fields if they exists 
as column names.
  
  my $user = My::User->new(
    login_name => 'fred',
    first_name => 'Fred',
    last_name =>'Flintstone');
  
  my $user = My::User->new({
    login_name => 'fred',
    first_name => 'Fred',
    last_name =>'Flintstone'
  });#HASHREF accepted too

=head2 new_from_dbix_simple

A constructor called in L<DBIx::Simple/object> and 
L<DBIx::Simple/objects>. Basically makes the same as C<new()> without 
checking the validity of the field values since they come from the 
database and should be valid. 
You will never ever need to call this directly but this example is provided 
to show how the DBIx::Simple::Class interacts with L<DBIx::Simple>. 
See L<DBIx::Simple/Advanced_object_construction>.

  my $class = 'My::Model::AdminUser';
  my @admins = $dbix->select(
    $class->TABLE,
    $class->COLUMNS,
    $class->WHERE
  )->objects($class);
  #one row
  my $admin = $class->select(id=>123});#see below
  
  My::User->query('SELECT * FROM users WHERE id=?',22)->login_name;
  #The above is about 3 times faster than this below
  $dbix->query('SELECT * FROM users WHERE id=?',2)
            ->object(':RowObject')->login_name;

=head2 query

A convenient wrapper for C<$dbix-E<gt>query($SQL,@bind)-E<gt>object($class)> 
and constructor. Accepts exactly the same arguments as L<DBIx::Simple/query>.
Returns an instance of your class on success or C<undef> otherwise.

  my $user = My::User->query(
    'SELECT ' . join (',',My::User->COLUMNS)
    . ' FROM ' . My::User->TABLE.' WHERE id=? and disabled=?', 12345, 0);

=head2 select

A convenient wrapper for 
C<$dbix-E<gt>select($table,$columns,$where)-E<gt>object($class)> and constructor. 
Note that L<SQL::Abstract> B<must be installed>. This is the only method 
that requires it. Have in mind that our L</query> is faster than this 
and you can use named queries via L</SQL>.

Instantiates an object from a saved in the database row by constructing and 
executing an SQL query based on the parameters. 
These parameters are used to construct the C<WHERE> clause for the SQL C<SELECT> 
statement. Prepends the L</WHERE> clause defined by you to the parameters. 
If a row is found, puts it in L</data>. 
Returns an instance of your class on success or C<undef> otherwise.

    # Build your WHERE using an SQL::Abstract structure:
    my $user = MYDLjE::M::User->select(id => $user_id);

=head2 select_by_pk

Retreives  a row from the L</TABLE> by L</PRIMARY_KEY>. 
Returns an instance of your class on success or C<undef> otherwise.

    my $user = My::User->select_by_pk(1234);



=head2 data

Common getter/setter for all L</COLUMNS>. 
Uses internally the specific field getter/setter for each field.
Returns a HASHREF - name/value pairs of the fields.

  $self->data(title=>'My Title', description =>'This is a great story.');
  my $hash = $self->data;
  #or
  $self->data($self->dbix->select(TABLE, COLUMNS, $where)->hash);

=head2 save

Intelligent saver. If the object is fresh 
( not instantiated via L</new_from_dbix_simple> and L</select>) prepares and 
executes an C<INSERT> statement, otherwise preforms an C<UPDATE>. 
L</TABLE> and L</COLUMNS> are used to construct the SQL. 
L</data> is stored as a row in L</TABLE>.
Returns the value of the internally performed operation. See below.

  my $note = MyNote->new(title=>'My Title', description =>'This is a great story.');
  #do something more...
  $note->save;

=head2 insert

Used internally in L</save>. Can be used when you are sure your object is 
not present in the table. Returns the value of the object L</PRIMARY_KEY>
on success. See L<DBIx::Simple/last_insert_id>.

    my $note = MyNote->new(title=>'My Title', description =>'This is a great story.');
    #do something more...
    my $last_insert_id = $note->insert;

=head2 update

Used internally in L</save>. Can be used when you are sure your object is 
retrieved from the table. Returns true on success.

  use My::Model::AdminUser;
  my $user = $dbix->query(
    'SELECT * FROM users WHERE login_name=?', 'fred'
  )->object('My::Model::AdminUser')
  $user->first_name('Fred')->last_name('Flintstone');
  $user->update;

=head2 SQL

A getter/setter for custom SQL code (named queries). 

Class method. 
You can add key/value pairs in your class and then use them in your application.
The values can be simple strings or subroutine references.
There are already some pre-made entries in this base class that you can 
use as example implementations. Look at the source for details.
The subroutine references are executed/evaluated only once and their output is 
cached for performance.

  package My::SiteUser;
  use base qw(My::User);#a subclass of DBIx::Simple::Class
  sub WHERE { {disabled => 0, group_id => 2} }
  
  #these could be very complex and retreived from a file where you keep them!
  __PACKAGE__->SQL(
    GUEST => 'SELECT * FROM users WHERE login_name = \'guest\'',
    DISABLED => sub{
        'SELECT * FROM'.__PACKAGE__->TABLE.' WHERE disabled=?';
    }
    LAST_N_REGISTERED => __PACKAGE__->SQL('SELECT')
        .' order by id desc LIMIT ?, ?'
  );

  1;
  # in your application
  $SU ='My::SiteUser';
  my $guest = $SU->query($SU->SQL('GUEST'));
  my @members = $SU->query($SU->SQL('SELECT'));#allll ;)
  my @disabled = $SU->query($SU->SQL('DISABLED'), 1);
  my @enabled = $SU->query($SU->SQL('DISABLED'), 0);

=head1 EXAMPLES

Please look at the test file C<t/01-dbix-simple-class.t> of the distribution 
for a wealth of examples.


=head1 AUTHOR

Красимир Беров, C<< <berov at cpan.org> >>

=head1 CREDITS

Jos Boumans for Params::Check

Juerd Waalboer for DBIx::Simple

Nate Wiger  and all contributors for SQL::Abstract

=head1 BUGS

Please report any bugs or feature requests to 
L<https://github.com/kberov/DBIx--Simple--Class/issues>. 
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


=head1 SEE ALSO

L<DBIx::Simple>, L<DBIx::Simple::Result::RowObject>, L<DBIx::Simple::OO> 
L<DBIx::Class>, L<Data::ObjectDriver>,L<Class::DBI>, L<Class::DBI::Lite>, 
L<SQL::Abstract>, L<Params::Check>
L<https://github.com/kberov/MYDLjE>


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Красимир Беров (Krasimir Berov).

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
