package DBIx::Simple::Class::Schema;
use strict;
use 5.10.1;
use warnings;
use Carp;
use parent 'DBIx::Simple::Class';

*_get_obj_args = \&DBIx::Simple::Class::_get_obj_args;

#struct to keep shemas while building
my $shemas = {};

#for accesing private $schemas from outside
sub schema {
  return $_[1] ? $shemas->{$_[1]} : $shemas;
}

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
  foreach my $table (@$tables) {
    $table->{column_info} =
      $class->dbh->column_info(undef, undef, $table->{TABLE_NAME}, '%')
      ->fetchall_arrayref({});
  }
  return $tables;
}

sub _generate_COLUMNS {
  my ($class, $tables) = @_;

  foreach my $t (@$tables) {
    $t->{COLUMNS} = [];
    foreach my $col (sort { $a->{ORDINAL_POSITION} <=> $a->{ORDINAL_POSITION} }
      @{$t->{column_info}})
    {
      push @{$t->{COLUMNS}}, $col->{COLUMN_NAME};
    }
  }

  #COLUMN_NAME: The column identifier.
  return $tables;
}

sub _generate_ALIASES {
  my ($class, $tables) = @_;
  foreach my $t (@$tables) {
    $t->{ALIASES} = {};
    foreach my $col (@{$t->{column_info}}) {

      #COLUMN_NAME: The column identifier.
      if ($col->{COLUMN_NAME} =~ /\W/) {    #not A-z0-9_
        $t->{ALIASES}{$col->{COLUMN_NAME}} = $col->{COLUMN_NAME};
        $t->{ALIASES}{$col->{COLUMN_NAME}} =~ s/\W/_/g;    #foo-bar=>foo_bar
      }
      elsif ($class->SUPER::can($col->{COLUMN_NAME})) {
        $t->{ALIASES}{$col->{COLUMN_NAME}} = 'column_' . $col->{COLUMN_NAME};
      }
    }
  }
  return $tables;
}

sub _generate_CHECKS {
  my ($class, $tables) = @_;
  foreach my $t (@$tables) {
    $t->{CHECKS} = {};
    foreach my $col (@{$t->{column_info}}) {
      if ($col->{IS_NULLABLE} eq 'NO') {
        $t->{CHECKS}{$col->{COLUMN_NAME}}{required} = 1;
        $t->{CHECKS}{$col->{COLUMN_NAME}}{defined}  = 1;
      }
      if ($col->{COLUMN_DEF}) {
        $t->{CHECKS}{$col->{COLUMN_NAME}}{default} = $col->{COLUMN_DEF};
      }
      my $size = $col->{COLUMN_SIZE};
      if ($size >= 65535) {
        $size = '';
      }
      if ($col->{TYPE_NAME} =~ /INT/i) {
        $t->{CHECKS}{$col->{COLUMN_NAME}}{allow} = qr/^-?\d{1,$size}$/x;
      }
      elsif ($col->{TYPE_NAME} =~ /CHAR|TEXT|CLOB/i) {
        $t->{CHECKS}{$col->{COLUMN_NAME}}{allow} = qr/^\d{1,$size}$/x;
      }
    }    #end column_info
  }    #end tables
  return $tables;

}

sub _generate_PRIMARY_KEY {
  my ($class, $tables) = @_;
  foreach my $table ($tables) {
    $class->dbh->primary_key_info(undef, undef, $table->{TABLE_NAME});
  }
  return $tables;
}

sub _generate_CODE {
  my ($class, $namespace) = @_;
  my $code   = '';
  my $schema = $class->schema($namespace);

  #base class
  $class->schema($namespace)->{code}{$namespace} = <<"BASE_CLASS";
package $namespace;
use string;
use warnings;
use parent 'DBIx::Simple::Class::Schema';

sub base_class{1}
1;
BASE_CLASS

  foreach (values %{$class->schema($namespace)->{code}}) {
    $code .= $_;
  }

  #TODO wallk the structure and build code

  return $code;
}

sub load_schema {
  my ($class, $args) = _get_obj_args(@_);
  $args->{namespace} ||= $class->dbh->{Name};
  $args->{namespace} = ucfirst(lc($args->{namespace} =~ s/\W//xg));
  $shemas->{$args->{namespace}} = {};

  #$shemas->{$args->{namespace}}{table_info}
  my $tables = $class->_get_table_info($args);

  #get table columns
  $class->_get_column_info($tables);

  #generate COLUMNS
  $class->_generate_COLUMNS($tables);

  #generate ALIASES
  #$table_info = $class->_generate_ALIASES($table_info);

  #generate PRIMARY_KEY
  #$table_info = $class->_generate_PRIMARY_KEY($table_info);

  #generate CHECKS
  #$table_info = $class->_generate_CHECKS($table_info);

  #generate code
  return $class->_generate_CODE($args->{namespace});
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

