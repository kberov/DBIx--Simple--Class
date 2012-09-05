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
can_ok($DSCS, qw(load_schema dump_schema_at));

#=pod
#create some tables
$dbix->query(<<'TAB');
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_id int(11) NOT NULL, -- COMMENT 'Primary group for this user'
  login_name varchar(100) NOT NULL,
  login_password varchar(100) NOT NULL, -- COMMENT 'Mojo::Util::md5_sum($login_name.$login_password)'
  name varchar(255) NOT NULL DEFAULT '',
  email varchar(255) NOT NULL DEFAULT 'email@domain.com',
  disabled tinyint(1) NOT NULL DEFAULT '0',
  balance DECIMAL(8,2) NOT NULL DEFAULT '0.00',
  UNIQUE(login_name) ON CONFLICT ROLLBACK,
  UNIQUE(email) ON CONFLICT ROLLBACK

)
TAB

#=cut

$dbix->query(<<'TAB');
CREATE TABLE groups(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  group_name VARCHAR(12),
  "is blocked" INT,
  data TEXT
  )
TAB
my $code = $DSCS->load_schema();
my $tables = $DSCS->_schemas('Memory')->{tables};
ok((grep { $_->{TABLE_NAME} eq 'users' || $_->{TABLE_NAME} eq 'groups' } @$tables),
  '_get_table_info works');
my @column_infos = (
  @{$tables->[0]->{column_info}},
  @{$tables->[1]->{column_info}},
  @{$tables->[2]->{column_info}}
);
is((grep { $_->{COLUMN_NAME} eq 'id' } @column_infos), 2, '_get_column_info works');
my %alaiases =
  (%{$tables->[0]->{ALIASES}}, %{$tables->[1]->{ALIASES}}, %{$tables->[2]->{ALIASES}});
is((grep { $_ eq 'is_blocked' || $_ eq 'column_data' } values %alaiases),
  2, '_generate_ALIASES works');

my %checks =
  (%{$tables->[0]->{CHECKS}}, %{$tables->[1]->{CHECKS}}, %{$tables->[2]->{CHECKS}});
like('alaba_anica2', qr/$checks{group_name}->{allow}/, 'checks VARCHAR(12) works fine');
unlike(
  'alaba_anica13',
  qr/$checks{group_name}->{allow}/,
  'checks VARCHAR(12) works fine'
);
like('1',  qr/$checks{id}->{allow}/, 'checks INT works fine');
like('11', qr/$checks{id}->{allow}/, 'checks INT works fine');
unlike('a', qr/$checks{id}->{allow}/, 'checks INT works fine');
like('1',          qr/$checks{data}->{allow}/, 'checks TEXT works fine');
like('11sd,asd,a', qr/$checks{data}->{allow}/, 'checks TEXT works fine');
unlike('', qr/$checks{'is blocked'}->{allow}/, 'checks TEXT works fine');
like('1', qr/$checks{disabled}->{allow}/, 'checks TINYINT(1) works fine');
unlike('11', qr/$checks{disabled}->{allow}/, 'checks TINYINT(1) works fine');
unlike('a',  qr/$checks{disabled}->{allow}/, 'checks TINYINT(1) works fine');
like('1',         qr/$checks{balance}->{allow}/, 'checks DECIMAL(8,2) works fine');
like('11.2',      $checks{balance}->{allow},     'checks DECIMAL(8,2) works fine');
like('123456.20', $checks{balance}->{allow},     'checks DECIMAL(8,2) works fine');
unlike('1234567.2', $checks{balance}->{allow},     'checks DECIMAL(8,2) works fine');
unlike('a',         qr/$checks{balance}->{allow}/, 'checks DECIMAL(8,2) works fine');
TODO: {
  local $TODO = "load_schema, dump_schema_at - not finished";

#load_schema
ok((eval{$code}),'code generated ok') or diag($@);
$DSCS->dump_schema_at();
#dump_schema_at

#dump_schema_at

#dump_class_at
}


done_testing;
