package    #hide
  My::App;
use strict;
use warnings;
use utf8;
use Data::Dumper;
use CGI qw(:standard :html3 *table);

use My;
use My::Group;
use My::User;


sub new {
  my $class = shift;
  my $self = bless {}, $class;
  return $self;
}

sub run {
  my $class = shift;

  #initialise
  my $app = $class->new();
  $app->initialise_db;
  my $action = 'action_' . (param('do') || 'list_users');
  warn $action . $app->can($action);

  #run
  if ($app->can($action)) {
    print header(
      -type    => 'text/html',
      -status  => '200 OK',
      -charset => 'utf-8',
      ),
      start_html($action), $app->$action(), end_html();
  }
  else {
    print header(
      -type    => 'text/html',
      -status  => '404 Not Found',
      -charset => 'utf-8',
      ),
      start_html(-title => 'Page Not Found'), h1('Page Not Found'), end_html();
  }
}


sub initialise_db {
  my $app = shift;
  DBIx::Simple::Class->DEBUG(1);

  my $dbix = DBIx::Simple->connect(
    "dbi:SQLite:dbname=$ENV{users_HOME}/db.sqlite",
    {sqlite_unicode => 1, RaiseError => 1}
  ) || die $DBI::errstr;
  DBIx::Simple::Class->dbix($dbix);
  $dbix->query(<<"TAB");
        CREATE TABLE IF NOT EXISTS groups(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_name VARCHAR(12),
          "foo-bar" VARCHAR(13),
          data TEXT
          )
TAB
  $dbix->query(<<"TAB");
        CREATE TABLE IF NOT EXISTS users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          group_id INT default 1,
          login_name VARCHAR(12),
          login_password VARCHAR(100), 
          disabled INT DEFAULT 1
          )
TAB

  sub My::Group::ALIASES {
    {data => 'group_data', 'foo-bar' => 'foo_bar'};
  }
  My::Group->QUOTE_IDENTIFIERS(1);
  My::User->QUOTE_IDENTIFIERS(1);

}

sub q { $_->{q} ||= CGI->new() }


#Controlers

sub action_list_users {
  my $app   = shift;
  my $out   = '';
  my $U     = 'My::User';
  my @users = My::User->query('SELECT * from users');
  my $rows  = [th([qw(id login_name login_password)]),];
  for (@users) {
    push @$rows, td([$_->id, $_->login_name, $_->login_password]);
  }
  $out
    .= start_table({-border => 1})
    . Tr({}, $rows)
    . end_table()
    . a({href => '?do=add_user'}, 'Add User');
  return $out;
}

sub action_add_user {
  my $app = shift;
  my $out = '';

  return $out;
}

sub action_list_groups {
  my $app    = shift;
  my $G      = 'My::Group';
  my @groups = $G->query('SELECT * from groups');
  my $out    = '';

  if (@groups) {

    #For your home work
  }
  else {
    $out .= h1('Please addd a group'), a({-href => 'action=add_group'}, 'Add');

  }

  return $out;
}

sub action_add_group {
  my $app = shift;
  my $out = '';

  #For your home work
  return $out;
}


1;
