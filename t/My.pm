use 5.010;
use strict;
use warnings;
use utf8;

use DBIx::Simple::Class;
{

  package My;    #our schema
  use base qw(DBIx::Simple::Class);
  sub namespace {__PACKAGE__}
}

{

  package My::User;
  use base qw(My);

  sub TABLE   {'users'}
  sub COLUMNS { [qw(id group_id login_name login_password disabled)] }
  sub WHERE   { {disabled => 1} }

  #See Params::Check
  my $_CHECKS = {
    id       => {allow => qr/^\d+$/x},
    group_id => {allow => qr/^\d+$/x, default => 1},
    disabled => {
      default => 1,
      allow   => sub {
        return $_[0] =~ /^[01]$/x;
        }
    },
    login_name     => {allow => qr/^\p{IsAlnum}{4,12}$/x},
    login_password => {
      required => 1,
      allow    => sub { $_[0] =~ /^[\w\W]{8,20}$/x; }
      }

      #...
  };
  sub CHECKS {$_CHECKS}

  sub id {
    my ($self, $value) = @_;
    if (defined $value) {    #setting value
      $self->{data}{id} = $self->_check(id => $value);

      #make it chainable
      return $self;
    }
    $self->{data}{id} //= $self->CHECKS->{id}{default};    #getting value
  }
}
{

  package My::Group;
  use base qw(My);

  use constant TABLE   => 'groups';
  use constant COLUMNS => [qw(id group_name foo-bar data)];
  use constant WHERE   => {};

  #See Params::Check
  use constant CHECKS => {};
}

{

  package My::Collision;
  use base qw(My);

  use constant TABLE   => 'collision';
  use constant COLUMNS => [qw(id data)];
  use constant WHERE   => {};
  use constant ALIASES => {data => 'column_data'};

  #CHECKS are on columns
  use constant CHECKS => {
    id   => {allow   => qr/^\d+$/x},
    data => {default => '',}           #that's ok
  };
}

{

  package My::SiteUser;
  use base qw(My::User);
  my $_CHECKS = My::User->CHECKS;
  $_CHECKS->{group_id}{default} = 3;
  sub CHECKS {$_CHECKS}
  sub WHERE { {disabled => 0, group_id => $_CHECKS->{group_id}{default}} }

  #merge with parent $SQL
  __PACKAGE__->SQL(GUEST_USER => 'SELECT * FROM users WHERE login_name = \'guest\'');
}

1;
