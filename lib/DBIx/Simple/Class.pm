package DBIx::Simple::Class;

use 5.10.1;
use strict;
use warnings;
use Params::Check;
use Carp;
use DBIx::Simple;

our $VERSION = '0.66';


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
sub CHECKS {
  croak(
    "You must define your CHECKS subroutine that returns your private \$_CHECKS HASHREF!"
  );
}

#default where
sub WHERE { {} }

sub PRIMARY_KEY {'id'}

sub ALIASES { {} }

my $QUOTE_IDENTIFIERS = {};

sub QUOTE_IDENTIFIERS {
  my $class  = shift;
  my $yes_no = shift;
  return $QUOTE_IDENTIFIERS->{$class} = $yes_no if defined $yes_no;
  return $QUOTE_IDENTIFIERS->{$class};
}

my $UNQUOTED = {};

sub _UNQUOTED {
  my ($class) = shift;    #class
  $class = ref $class if ref $class;
  return $UNQUOTED->{$class} ||= {};
}

#for outside modification during tests
my $_attributes_made = {};
sub _attributes_made {$_attributes_made}
my $SQL_CACHE = {};
sub _SQL_CACHE {$SQL_CACHE}

my $SQL = {};
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

  _LIMIT => sub {

#works for MySQL, SQLite, PostgreSQL
#TODO:See SQL::Abstract::Limit for other implementations
#and implement it using this technique.
    " LIMIT $_[1]" . ($_[2] ? " OFFSET $_[2] " : '');
  },
};

sub SQL_LIMIT {
  my $_LIMIT = $SQL->{_LIMIT};
  return $_LIMIT->(@_);
}

sub SQL {
  my ($class, $args) = _get_obj_args(@_);    #class
  croak('This is a class method. Do not use as object method.') if ref $class;

  if (ref $args) {                           #adding new SQL strings($k=>$v pairs)
    return $SQL->{$class} = {%{$SQL->{$class} || $SQL}, %$args};
  }

  #a key
  if ($args && !ref $args) {

    #do not return hidden keys
    croak("Named query '$args' can not be used directly") if $args =~ /^_+/x;

    #allow subclasses to override parent sqls and cache produced SQL
    my $_SQL =
         $SQL_CACHE->{$class}{$args}
      || $SQL->{$class}{$args}
      || $SQL->{$args}
      || $args;
    if (ref $_SQL) {
      return $_SQL->(@_);
    }
    else {
      return $_SQL;
    }
  }

  #they want all
  return $SQL;
}


#ATTRIBUTES

#copy/paste/override this method in your base schema classes
#if you want more instances per application
sub dbix {

  # Singleton DBIx::Simple instance
  state $DBIx;
  return ($DBIx = $_[1] ? $_[1] : $DBIx) || croak('DBIx::Simple is not instantiated');
}
sub dbh { $_[0]->dbix->dbh }

#METHODS

sub new {
  my ($class, $fields) = _get_obj_args(@_);
  local $Params::Check::WARNINGS_FATAL = 1;
  local $Params::Check::CALLER_DEPTH   = $Params::Check::CALLER_DEPTH + 1;

  $fields = Params::Check::check($class->CHECKS, $fields)
    || croak(Params::Check::last_error());
  $class->BUILD()
    unless $_attributes_made->{$class};
  return bless {data => $fields}, $class;
}

sub new_from_dbix_simple {
  $_attributes_made->{$_[0]} || $_[0]->BUILD();
  if (wantarray) {
    return (map { bless {data => $_, new_from_dbix_simple => 1}, $_[0]; }
        @{$_[1]->{st}->{sth}->fetchall_arrayref({})});
  }
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
  $class->new_from_dbix_simple(
    $class->dbix->select($class->TABLE, $class->COLUMNS, {%{$class->WHERE}, %$where}));
}

sub query {
  my $class = shift;
  $class->new_from_dbix_simple($class->dbix->query(@_));
}

sub select_by_pk {
  my ($class, $pk) = @_;
  return $class->new_from_dbix_simple(
    $class->dbix->query(
      $SQL_CACHE->{$class}{SELECT_BY_PK} || $class->SQL('SELECT_BY_PK'), $pk
    )
  );
}

{
  no warnings qw(once);
  *find = \&select_by_pk;
}

sub BUILD {
  my $class = shift;
  (!ref $class)
    || croak("Call this method as $class->BUILD()");
  $class->_UNQUOTED->{TABLE}   = $class->TABLE;
  $class->_UNQUOTED->{WHERE}   = {%{$class->WHERE}};      #copy
  $class->_UNQUOTED->{COLUMNS} = [@{$class->COLUMNS}];    #copy

  my $code = '';
  foreach (@{$class->_UNQUOTED->{COLUMNS}}) {

    my $alias = $class->ALIASES->{$_} || $_;
    croak("You can not use '$alias' as a column name since it is already defined in "
        . __PACKAGE__
        . '. Please define an \'alias\' for the column to be used as method.')
      if __PACKAGE__->can($alias);
    next if $class->can($alias);                          #careful: no redefine
    $code = "use strict;$/use warnings;$/use utf8;$/" unless $code;
    $code .= <<"SUB";
sub $class\::$alias {
  my (\$self,\$value) = \@_;
  if(defined \$value){ #setting value
  \$self->{data}{qq{$_}} = \$self->_check(qq{$_}=>\$value);
    #make it chainable
    return \$self;
  }
  \$self->{data}{qq{$_}}
  //= \$self->CHECKS->{qq{$_}}{default}; #getting value
}

SUB

  }

  my $dbh = $class->dbh;
  if ($class->QUOTE_IDENTIFIERS) {
    $code
      .= 'no warnings qw"redefine";'
      . "sub $class\::TABLE {'"
      . $dbh->quote_identifier($class->TABLE) . "'}";
    my %where = %{$class->WHERE};
    $code .= "sub $class\::WHERE {{";
    for (keys %where) {
      $code
        .= 'qq{'
        . $dbh->quote_identifier($_)
        . '}=>qq{'
        . $dbh->quote($where{$_}) . '}, '
        . $/;
    }
    $code .= '}}#end WHERE' . $/;
    my @columns = @{$class->COLUMNS};
    $code .= "sub $class\::COLUMNS {[";
    for (@columns) {
      $code .= 'qq{' . $dbh->quote_identifier($_) . '},';
    }
    $code .= ']}#end COLUMNS' . $/;
  }    #if ($class->QUOTE_IDENTIFIERS)
  $code .= "$/1;";

  #I know what I am doing. I think so...
  unless (eval $code) {    ##no critic (BuiltinFunctions::ProhibitStringyEval)
    croak($class . " compiler error: $/$code$/$@$/");
  }
  if ($class->DEBUG) {
    carp($class . " generated accessors: $/$code$/$@$/");
  }
  $dbh->{Callbacks}{prepare} = sub {
    return unless $DEBUG;
    my ($dbh, $query, $attrs) = @_;
    my ($package, $filename, $line, $subroutine) = caller(1);
    carp("SQL from $subroutine in $filename:$line :\n$query\n");
    return;
  };

  #make sure we die loudly
  $dbh->{RaiseError} = 1;
  return $_attributes_made->{$class} = 1;
}


#conveninece for getting key/vaule arguments
sub _get_args {
  return ref($_[0]) ? shift() : (@_ % 2) ? shift() : {@_};
}
sub _get_obj_args { return (shift, _get_args(@_)); }

sub _check {
  my ($self, $key, $value) = @_;
  local $Params::Check::WARNINGS_FATAL = 1;
  local $Params::Check::CALLER_DEPTH   = $Params::Check::CALLER_DEPTH + 1;

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
      unless ($field ~~ @{$self->_UNQUOTED->{COLUMNS}}) {
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
  my $dbh = $self->dbh;
  $self->{SQL_UPDATE} ||= do {
    my $SET =
      join(', ', map { $dbh->quote_identifier($_) . '=? ' } keys %{$self->{data}});
    'UPDATE ' . $self->TABLE . " SET $SET WHERE $pk=?";
  };
  return $dbh->prepare($self->{SQL_UPDATE})
    ->execute(values %{$self->{data}}, $self->{data}{$pk});
}

sub insert {
  my ($self) = @_;
  my ($pk, $class) = ($self->PRIMARY_KEY, ref $self);

  $self->dbh->prepare($SQL_CACHE->{$class}{INSERT} || $class->SQL('INSERT'))->execute(
    map {

      #set expected defaults
      $self->data($_)
    } @{$class->_UNQUOTED->{COLUMNS}}
  );

  #user set the primary key already
  return $self->{data}{$pk}
    ||= $self->dbh->last_insert_id(undef, undef, $self->TABLE, $pk);

}


1;

__END__


# If you have pod after  __END__,
#comment __END__ marker so you can generate/use
# additional perl tags using exuberant ctags.

# Example ctags filters to put in your ~/.ctags file:
#--regex-perl=/^\s*?use\s+(\w+[\w\:]*?\w*?)/\1/u,use,uses/
#--regex-perl=/^\s*?require\s+(\w+[\w\:]*?\w*?)/\1/r,require,requires/
#--regex-perl=/^\s*?has\s+['"]?(\w+)['"]?/\1/a,attribute,attributes/
#--regex-perl=/^\s*?\*(\w+)\s*?=/\1/a,aliase,aliases/
#--regex-perl=/->helper\(\s?['"]?(\w+)['"]?/\1/h,helper,helpers/
#--regex-perl=/^\s*?our\s*?[\$@%](\w+)/\1/o,our,ours/
#--regex-perl=/^=head1\s+(.+)/\1/p,pod,Plain Old Documentation/
#--regex-perl=/^=head2\s+(.+)/-- \1/p,pod,Plain Old Documentation/
#--regex-perl=/^=head[3-5]\s+(.+)/---- \1/p,pod,Plain Old Documentation/


