package DBIx::Simple::Class::Schema;
use strict;
use 5.10.1;
use warnings;
use Carp;
use parent 'DBIx::Simple::Class';
*_get_obj_args = \&DBIx::Simple::Class::_get_obj_args;

sub load_schema {
  my ($class, $args) = _get_obj_args(@_);

  #see https://metacpan.org/module/DBI#table_info
  my $tables = $class->dbh->table_info(
    undef, undef,
    $args->{table} || '%',
    $args->{type}  || "'TABLE','VIEW'"
  )->fetchall_arrayref({});

  #return $tables;
  my $tables_columns = {};
  foreach my $table (@$tables) {
    $tables_columns->{$table->{TABLE_NAME}} =
      $class->dbh->column_info(undef, undef, $table->{TABLE_NAME}, '%')
      ->fetchall_arrayref({});
  }
  return $tables_columns;
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



=head1 LICENSE AND COPYRIGHT

Copyright 2012 Красимир Беров (Krasimir Berov).

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

See http://dev.perl.org/licenses/ for more information.

