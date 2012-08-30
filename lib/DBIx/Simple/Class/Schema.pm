package DBIx::Simple::Class::Schema;
use strict;
use 5.10.1;
use warnings;
use Carp;
use parent 'DBIx::Simple::Class';
*_get_obj_args = \&DBIx::Simple::Class::_get_obj_args;

sub _get_table_info {
  my ($class, $args) = _get_obj_args(@_);

  #get tables from the current database
  #see https://metacpan.org/module/DBI#table_info
  return $class->dbh->table_info(
    undef, undef,
    $args->{table} || '%',
    $args->{type}  || "'TABLE','VIEW'"
  )->fetchall_arrayref({});

}

sub _get_column_info {
  my ($class, $tables) = @_;
  my $tables_with_columns = {};
  foreach my $table (@$tables) {
    $tables_with_columns->{$table->{TABLE_NAME}}{column_info} =
      $class->dbh->column_info(undef, undef, $table->{TABLE_NAME}, '%')
      ->fetchall_arrayref({});
  }
  return $tables_with_columns;
}

sub _generate_COLUMNS {
  my ($class, $tables) = @_;

  #COLUMN_NAME: The column identifier.
}

sub _generate_ALIASES {
  my ($class, $tables) = @_;

  #COLUMN_NAME: The column identifier.
}

sub _generate_CHECKS {
  my ($class, $tables) = @_;
  #

}

sub _generate_PRIMARY_KEY {
  my ($class, $tables) = @_;
  foreach my $table ($tables) {
    $class->dbh->primary_key_info(undef, undef, $table->{TABLE_NAME});
  }
  return $tables;
}

sub _generate_CODE {
  my ($class, $tables) = @_;
  my $code = '';

  return $code;
}

sub load_schema {
  my ($class, $args) = _get_obj_args(@_);
  $args->{namespace}
    || Carp::croak(
    'Please provide "namespace"' . ' (e.g. My::Model) for your classes. ');

  my $table_info = $class->_get_table_info($args);

  #return $tables;
  #get table columns
  $table_info = $class->_get_column_info($table_info);

  #generate COLUMNS
  $table_info = $class->_generate_COLUMNS($table_info);

  #generate ALIASES
  $table_info = $class->_generate_ALIASES($table_info);

  #generate PRIMARY_KEY
  $table_info = $class->_generate_PRIMARY_KEY($table_info);

  #generate CHECKS
  $table_info = $class->_generate_CHECKS($table_info);

  #generate code
  return $class->_generate_CODE($table_info);
}


sub dump_schema_at {

}

sub dump_class_at {

}

1;

__END__

=encoding utf8

=head1 NAME

DBIx::Simple::Class::Schema - Create and use a DBIx::Simple::Class schema from a database

=head1 SYNOPSIS

  #Somewhere in a utility script or startup() fo your application.
  DBIx::Simple::Class::Schema->dbix(DBIx::Simple->connect(...));
  my $perl_code = DBIx::Simple::Class::Schema->load_schema(
    namespace =>'My::Model',
    table => '%',#all tables from the current database
    type  => "'TABLE','VIEW'"# make classes for tables and views
  );

  #Now eval() to use your classes.
  eval $perl_code|| croak($@);

  #Or save it for more customisations and later usage.
  DBIx::Simple::Class::Schema->dump_schema_at(
    code => $perl_code,
    root => "$ENV{HOME}/$ENV{PERL_LOCAL_LIB_ROOT}/lib"
    overwrite =>1 #overwrite existing files
  );


=head1 DESCRIPTION


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Красимир Беров (Krasimir Berov).

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

See http://dev.perl.org/licenses/ for more information.

