#!perl

use 5.10.1;
use strict;
use warnings;
use utf8;
use Test::More;


BEGIN {
  eval { require DBD::SQLite; 1 }
    or plan skip_all => 'DBD::SQLite required';
  eval { DBD::SQLite->VERSION >= 1 }
    or plan skip_all => 'DBD::SQLite >= 1.00 required';
  use File::Basename 'dirname';
  use Cwd;
  use lib (Cwd::abs_path(dirname(__FILE__) . '/..') . '/examples/lib');
}


use DBI::Const::GetInfoType;
use Data::Dumper;
use_ok('DBIx::Simple::Class::Schema');

my $DSCS = 'DBIx::Simple::Class::Schema';
my $dbix = DBIx::Simple->connect('dbi:SQLite:dbname=:memory:', {sqlite_unicode => 1});
isa_ok(ref($DSCS->dbix($dbix)), 'DBIx::Simple');
can_ok($DSCS, qw(load_schema dump_schema_at dump_class_at));

#create some tables
$dbix->query(<<'TAB');
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id int(11) NOT NULL, -- COMMENT 'Primary group for this user'
  login_name varchar(100) NOT NULL,
  login_password varchar(100) NOT NULL, -- COMMENT 'Mojo::Util::md5_sum($login_name.$login_password)'
  first_name varchar(255) NOT NULL DEFAULT '',
  last_name varchar(255) NOT NULL DEFAULT '',
  email varchar(255) NOT NULL DEFAULT 'email@domain.com',
  description varchar(255) DEFAULT NULL,
  created_by int(11) NOT NULL DEFAULT '1',  -- COMMENT 'id of who created this user.'
  changed_by int(11) NOT NULL DEFAULT '1', -- COMMENT 'Who modified this user the last time?'
  tstamp int(11) NOT NULL DEFAULT '0', -- COMMENT 'last modification time'
  reg_tstamp int(11) NOT NULL DEFAULT '0', -- COMMENT 'registration time'
  disabled tinyint(1) NOT NULL DEFAULT '0',
  start int(11) NOT NULL DEFAULT '0',
  stop int(11) NOT NULL DEFAULT '0',
  properties blob, -- COMMENT 'Serialized/cached properties inherited and overided from group'
  UNIQUE(login_name) ON CONFLICT ROLLBACK,
  UNIQUE(email) ON CONFLICT ROLLBACK

)
TAB

$dbix->query(<<'TAB');
CREATE TABLE groups(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_name VARCHAR(12)
  )
TAB


TODO: {
  local $TODO = "load_schema, dump_schema_at and dump_class_at  not finished";

#load_schema
#warn Dumper($DSCS->load_schema);

#dump_schema_at

#dump_class_at
}


my $dbh = $dbix->dbh;
my $tsth = $dbh->table_info(undef, '%main%', '%%', "table", {});

#warn Dumper($tsth->fetchall_arrayref({}));
foreach (keys %GetInfoType) {
my $i;
#say $_.': '. ($i = $dbh->get_info($GetInfoType{$_})|| '');
#say "     $i" if $_ =~/sche/i;
}

{
  no strict 'refs';
  foreach (@{$DBI::EXPORT_TAGS{sql_types}}) {

    #printf "%s=%d\n", $_, &{"DBI::$_"};
  }
}
done_testing;
