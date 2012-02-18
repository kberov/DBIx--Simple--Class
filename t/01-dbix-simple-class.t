#!perl -T

use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;


BEGIN {
  eval { require DBD::SQLite; 1 }
    or plan skip_all => 'DBD::SQLite required';
  eval { DBD::SQLite->VERSION >= 1 }
    or plan skip_all => 'DBD::SQLite >= 1.00 required';
}
use DBIx::Simple::Class;
my $DSC = 'DBIx::Simple::Class';

# In memory database! No file permission troubles, no I/O slowness.
# http://use.perl.org/~tomhukins/journal/31457 ++

my $dbix = DBIx::Simple->connect('dbi:SQLite:dbname=:memory:', {sqlite_unicode => 1});

#$DSC->DEBUG(1);
is($DSC->DEBUG,    0);
is($DSC->DEBUG(1), 1);
is($DSC->DEBUG(0), 0);
like((eval { $DSC->dbix }, $@), qr/not instantiated/);
like((eval { $DSC->dbix('') }, $@), qr/not instantiated/);
isa_ok(ref($DSC->dbix($dbix)), 'DBIx::Simple');
isa_ok(ref($DSC->dbix),        'DBIx::Simple');

like((eval { $DSC->TABLE },   $@), qr/table-name for your class/);
like((eval { $DSC->COLUMNS }, $@), qr/fields for your class/);
like((eval { $DSC->CHECKS },  $@), qr/define your CHECKS subroutine/);
is(ref($DSC->WHERE), 'HASH');

my $groups_table = <<"T";
CREATE TABLE groups(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_name VARCHAR(12)
  )
T
my $users_table = <<"T";
CREATE TABLE users(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id INT default 1,
  login_name VARCHAR(12),
  login_password VARCHAR(100), 
  disabled INT DEFAULT 1
  )
T

$dbix->query($groups_table);
$dbix->query($users_table);

{

  package My::User;
  use base qw(DBIx::Simple::Class);

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
  1;
}

#$DSC->DEBUG(1);
isa_ok(ref(My::User->dbix),        'DBIx::Simple');
isa_ok(ref(My::User->dbix($dbix)), 'DBIx::Simple');
is(My::User->TABLE, 'users');
is_deeply(My::User->COLUMNS, [qw(id group_id login_name login_password disabled)]);
is(ref(My::User->WHERE), 'HASH');
is_deeply(My::User->WHERE, {disabled => 1});
my $user;
my $password = time;
like(
  (eval { $user = My::User->new() }, $@),
  qr/Required option/,
  '"Required option" ok'
);


ok($user = My::User->new(login_password => $password));

like(
  (eval { $user->_make_field_attrs() }, $@),
  qr/Call this method as/,
  '_make_field_attrs() ok'
);
is(
  My::User->_make_field_attrs(),
  $DSC->_attributes_made->{'My::User'},
  'if (eval $code) in _make_field_attrs() ok'
);
isa_ok(ref($user), $DSC);

#defaults
is($user->id, undef, 'id is undefined ok');
is($user->group_id, $user->CHECKS->{group_id}{default}, 'group_id default ok');
delete $user->CHECKS->{group_id}{default};
delete $user->{data}->{group_id};
is($user->group_id, $user->CHECKS->{group_id}{default}, 'group_id default ok');
is($user->login_name, undef, 'login_name is undefined ok');
is($user->login_password, $password, 'login_password is defined ok');
is($user->disabled, $user->CHECKS->{disabled}{default}, 'disabled by default ok');

#invalid
my $type_error = qr/\sis\sof\sinvalid\stype/x;
like((eval { $user->id('bar') },       $@), $type_error, "id is invalid ok");
like((eval { $user->group_id('bar') }, $@), $type_error, "group_id is invalid ok");

like((eval { $user->login_name('sakdk-') }, $@), $type_error, "login_name_error ok");
like((eval { $user->login_name('пет') }, $@),
  $type_error, 'login_name is shorter ok');
like((eval { $user->login_name('петърparvanov') }, $@),
  $type_error, 'login_name is longer ok');

like((eval { $user->login_password('тайнаtа') }, $@),
  $type_error, 'login_password is shorter ok');
like((eval { $user->login_password('тайнаtатайнаtатайнаtа') }, $@),
  $type_error, 'login_password is longer ok');

like((eval { $user->disabled('foo') }, $@), $type_error, 'disabled is invalid ok');
like((eval { $user->disabled(5) },     $@), $type_error, 'disabled is longer ok');

#valid
ok($user->login_name('петър')->login_name, 'login_name is valid');
ok($user->login_password('петър123342%$')->login_password,
  'login_password is valid');
ok($user->disabled(0), 'disabled is valid');
is($user->disabled, 0, 'disabled is valid');

#data
is($user->data->{disabled}, 0, 'disabled via data is valid');
is($user->data('disabled'), 0, 'disabled via data is valid');
is($user->data(disabled => 0, group_id => 2)->{group_id},
  2, 'disabled via data is valid');
is(ref $user->data, 'HASH', 'disabled via data is valid');


{

  package My::Group;
  use base qw(DBIx::Simple::Class);

  use constant TABLE   => 'groups';
  use constant COLUMNS => [qw(id group_name foo-bar data)];
  use constant WHERE   => {};

  #See Params::Check
  use constant CHECKS => {};
  1;
}
my $group;

like(
  (eval { My::Group->new() }, $@),
  qr/You can not use .+? as a column name/,
  '"You can not use \'data\' as a column name" ok'
);

delete My::Group->COLUMNS->[-1];
like(
  (eval { My::Group->new() }, $@),
  qr/Illegal declaration of subroutine/,
  '"Illegal declaration of subroutine" ok'
);
delete My::Group->COLUMNS->[-1];

is_deeply(My::Group->COLUMNS, [qw(id group_name)]);

like(
  (eval { My::Group->new(description => 'tralala') }, $@),
  qr/is not a valid key for/,
  '"is not a valid key for" ok'
);
My::Group->DEBUG(1);
like(
  (eval { My::Group->new->data('lala') }, $@),
  qr/Can't locate object method "lala" via package "My::Group"/,
  '"is not a valid key for" ok'
);
ok(My::Group->can('id'),         'can id');
ok(My::Group->can('group_name'), 'can group_name');
ok($group = My::Group->new);
ok($group->id(1));
ok($group->data('lala' => 1));
is_deeply($group->data(), {id => 1}, '"There is not such field lala" ok');
My::Group->DEBUG(0);

#insert
My::Group->CHECKS->{id}         = {allow => qr/^\d+$/};
My::Group->CHECKS->{group_name} = {allow => qr/^\p{IsAlnum}{3,12}$/x};
ok($group = My::Group->new(group_name => 'admin'));
is((eval { $group->save } || $@), 1, 'ok inserted group:' . $group->id);

#update
is(($group->group_name('admins')->save && $group->id),
  1, 'ok updated group:' . $group->id);
ok($group = $dbix->query('select*from groups where id=1')->object('My::Group'));
is($group->group_name, 'admins', 'group name is equal');
my $g2;
ok($g2 = My::Group->new(group_name => 'guests'));
is(($g2->save(group_name => 'users') && $g2->group_name),
  'users', 'new group_name "' . $g2->group_name . '" with params to save ok');

is($user->group_id($group->id)->group_id, 1, 'added user to group ok');
is($user->save,                           1, 'user inserted ok');
delete $DSC->_attributes_made->{'My::User'};
ok(
  $user =
    $dbix->query('select*from users where login_name=?', $user->login_name)
    ->object('My::User'),
  'user retrieved from database ok'
);

if (eval { My::User->dbix->abstract }) {
  is_deeply(My::User->select(id => $user->id, disabled => 0)->data,
    $user->data, 'select works!');
  is_deeply(My::User->select(id => $user->id)->data, undef, 'wrong select works!');
}
is_deeply(
  My::User->query('select * from users where id=? and disabled=?', $user->id, 0)->data,
  $user->data,
  'select works!'
);
is_deeply(
  My::User->query('select * from users where id=? and disabled=?', $user->id, 1)->data,
  undef,
  'wrong select works!'
);

#test column=>method collision
my $collision_table = <<"T";
CREATE TABLE collision(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  data TEXT
  )
T

$dbix->query($collision_table);
{

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
}
my $coll;
isa_ok($coll = My::Collision->new(data => 'some text'),
  'My::Collision', '"column=>alias" ok');

#use it
is_deeply($coll->column_data('bar')->data, {data => 'bar'}, 'alias() sets ok');
is($coll->column_data, 'bar', 'alias() gets ok');
is_deeply($coll->data('data'), 'bar', 'data() gets ok');
is_deeply($coll->data('data' => 'foo'), {data => 'foo'}, 'data() sets ok');
is($coll->save, 1, 'alias() inserts ok');
$coll = My::Collision->query('select * from collision where id=1');
is_deeply($coll->data, {data => 'foo', id => 1}, 'alias() query ok');
if (eval { My::Collision->dbix->abstract }) {
  $coll = My::Collision->select(id => 1);
  is_deeply($coll->data, {data => 'foo', id => 1}, 'alias() select ok');
}
ok($coll->column_data('barababa')->save, 'alias() updates ok');
is(
  $coll->column_data,
  My::Collision->query('select * from collision where id=1')->column_data,
  'alias() updates ok2'
);

#test getting by primary key
My::Collision->new(data => 'second id')->save;
is(My::Collision->select_by_pk(2)->id, 2, 'select_by_pk ok');
is(My::Collision->select_by_pk(2)->id, 2, 'select_by_pk ok from $SQL_CACHE');

#testing SQL
my $site_group = My::Group->new(group_name => 'SiteUsers');
$site_group->save;

{

  package My::SiteUser;
  use base qw(My::User);
  sub WHERE { {disabled => 0, group_id => 2} }

  #merge with parent $SQL
  __PACKAGE__->SQL(GUEST_USER => 'SELECT * FROM users WHERE login_name = \'guest\'');

  1;
}
my $SCLASS = 'My::SiteUser';
isa_ok($SCLASS->SQL(FOO => 'SELECT * FROM foo'), 'HASH', 'SQL(FOO=>...) is setting ok');
is(
  $SCLASS->SQL(FOO => 'SELECT * FROM foo') && $SCLASS->SQL('FOO'),
  'SELECT * FROM foo',
  'SQL(FOO=>...) is setting ok2'
);
like($SCLASS->SQL('SELECT'),       qr/FROM\s+users/x,     'SQL(SELECT) is getting ok');
like(My::Collision->SQL('SELECT'), qr/FROM\s+collision/x, 'SQL(SELEC) is getting ok2');
like(
  $SCLASS->SQL('GUEST_USER'),
  qr/SELECT \* FROM users/,
  'SQL(GUEST_USER) is getting ok'
);

like((eval { $DSC->SQL('SELECT') } || $@), qr/fields for your class/,
  'SQL() croaks ok');

$SCLASS->new(login_name => 'guest', login_password => time . 'QW')
  ->group_id($site_group->id)->save;

my $guest = $SCLASS->query($SCLASS->SQL('SELECT') . ' AND id=?', 1);
$guest = $SCLASS->select_by_pk(1);
is(
  $SCLASS->SQL('BY_PK'),
  $DBIx::Simple::Class::SQL_CACHE->{$SCLASS}{BY_PK},
  'SQL() is getting ok'
);

like(
  $SCLASS->SQL('SELECT'),
  qr/SELECT.+FROM\s+users\sWHERE\sdisabled.+group_id='2'/x,
  'SELECT generated ok'
);

done_testing();
