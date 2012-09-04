package DBIx::Simple::Class::Schema;
use strict;
use 5.10.1;
use warnings;
use Carp;
use parent 'DBIx::Simple::Class';
use Data::Dumper;

*_get_obj_args = \&DBIx::Simple::Class::_get_obj_args;

#struct to keep schemas while building
my $schemas = {};


sub _get_table_info {
  my ($class, $args) = _get_obj_args(@_);

  #get tables from the current database
  #see https://metacpan.org/module/DBI#table_info
  return $schemas->{$args->{namespace}}{tables} = $class->dbh->table_info(
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

#generates COLUMNS and PRIMARY_KEY
sub _generate_PRIMARY_KEY_COLUMNS_ALIASES_CHECKS {
  my ($class, $tables) = @_;

  foreach my $t (@$tables) {

    $t->{PRIMARY_KEY} =
      $class->dbh->primary_key_info(undef, undef, $t->{TABLE_NAME})
      ->fetchall_arrayref({})->[0]->{COLUMN_NAME} ||'';

    $t->{COLUMNS} = [];
    $t->{ALIASES} = {};
    $t->{CHECKS}  = {};
    $t->{QUOTE_IDENTIFIERS} = 0;
    foreach my $col (sort { $a->{ORDINAL_POSITION} <=> $b->{ORDINAL_POSITION} }
      @{$t->{column_info}})
    {
      push @{$t->{COLUMNS}}, $col->{COLUMN_NAME};
      
      #generate ALIASES
      if ($col->{COLUMN_NAME} =~ /\W/) {    #not A-z0-9_
        $t->{QUOTE_IDENTIFIERS} = 1;
        $t->{ALIASES}{$col->{COLUMN_NAME}} = $col->{COLUMN_NAME};
        $t->{ALIASES}{$col->{COLUMN_NAME}} =~ s/\W/_/g;    #foo-bar=>foo_bar
      }
      elsif ($class->SUPER::can($col->{COLUMN_NAME})) {
        $t->{ALIASES}{$col->{COLUMN_NAME}} = 'column_' . $col->{COLUMN_NAME};
      }

      # generate CHECKS
      if ($col->{IS_NULLABLE} eq 'NO') {
        $t->{CHECKS}{$col->{COLUMN_NAME}}{required} = 1;
        $t->{CHECKS}{$col->{COLUMN_NAME}}{defined}  = 1;
      }
      if ($col->{COLUMN_DEF}) {
        my $default = $col->{COLUMN_DEF};
        $default =~ s|\'||g;
        $t->{CHECKS}{$col->{COLUMN_NAME}}{default} = $default;
      }
      my $size = $col->{COLUMN_SIZE} // 0;
      if ($size >= 65535 || $size == 0) {
        $size = '';
      }
      if ($col->{TYPE_NAME} =~ /INT/i) {
        $t->{CHECKS}{$col->{COLUMN_NAME}}{allow} = qr/^-?\d{1,$size}$/x;
      }
      elsif ($col->{TYPE_NAME} =~ /FLOAT|DOUBLE|DECIMAL/i) {
        my $scale     = $col->{DECIMAL_DIGITS};
        my $precision = $size - $scale;
        $t->{CHECKS}{$col->{COLUMN_NAME}}{allow} =
          qr/^-?\d{1,$precision}(?:\.\d{1,$scale})?$/x;
      }
      elsif ($col->{TYPE_NAME} =~ /CHAR|TEXT|CLOB/i) {
        $t->{CHECKS}{$col->{COLUMN_NAME}}{allow} = qr/^.{1,$size}$/x;
      }
    }    #end foreach @{$t->{column_info}
  }    #end foreach $tables
  return $tables;
}


sub generate_CODE {
  my ($class, $args) = @_;
  my $code      = '';
  my $namespace = $args->{namespace};
  my $tables = $schemas->{$namespace}{tables};
  $schemas->{$namespace}{code}=[];

  push @{$schemas->{$namespace}{code}}, <<"BASE_CLASS";
package $namespace;
use string;
use warnings;
use parent 'DBIx::Simple::Class';

sub base_class{1}
1;
BASE_CLASS


  foreach my $t (@$tables) {
    my $package = $namespace . '::' . ucfirst(lc($t->{TABLE_NAME}));
    my $COLUMNS = Data::Dumper->Dump([$t->{COLUMNS}],['$COLUMNS']);
    my $ALIASES = Data::Dumper->Dump([$t->{ALIASES}],['$ALIASES']);
    my $CHECKS = Data::Dumper->Dump([$t->{CHECKS}],['$CHECKS']);
    my $TABLE = Data::Dumper->Dump([$t->{TABLE_NAME}],['$TABLE_NAME']);
    push @{$schemas->{$namespace}{code}}, <<"TABLE_CLASS";
package $package;
use string;
use warnings;
use parent '$namespace';

sub base_class{0}
my $TABLE
sub TABLE { \$TABLE_NAME }
sub PRIMARY_KEY{'$t->{PRIMARY_KEY}'}
my $COLUMNS
sub COLUMNS { \$COLUMNS }
my $ALIASES
sub ALIASES { \$ALIASES }
my $CHECKS
sub CHECKS { \$CHECKS }

__PACKAGE__->QUOTE_IDENTIFIERS($t->{QUOTE_IDENTIFIERS});
#__PACKAGE__->BUILD;#build accessors during load

1;

__END__

=pod 

=encoding utf8

=head1 NAME

$package - A class for $t->{TABLE_TYPE} $t->{TABLE_NAME} in $t->{column_info}[0]{TABLE_SCHEM}

=head1 SYNOPSIS


=head1 DESCRIPTION



=head1 COLUMNS

Each column in this class has an accessor.

=head1 ALIASES


=head1 GENERATOR

L<${\(__PACKAGE__)}>

=head1 SEE ALSO

L<$namespace>,
L<DBIx::Simple::Class>, L<${\(__PACKAGE__)}>


TABLE_CLASS

  }# end foreach my $t (@$tables)
  if(defined wantarray){
    foreach (@{$schemas->{$namespace}{code}}) {
      $code .= $_;
    }
  }
  #TODO wallk the structure and build code

  return $code;
}

sub load_schema {
  my ($class, $args) = _get_obj_args(@_);
  unless ($args->{namespace}) {
    $args->{namespace} = $class->dbh->{Name};
    if ($args->{namespace} =~ /(database|dbname|db)=([^;]+);?/x) {
      $args->{namespace} = $2;
    }
    $args->{namespace} =~ s/\W//xg;
    $args->{namespace} = ucfirst(lc($args->{namespace}));
  }

  my $tables = $class->_get_table_info($args);

  #get table columns
  $class->_get_column_info($tables);

  #generate COLUMNS, PRIMARY_KEY, ALIASES, CHECKS
  $class->_generate_PRIMARY_KEY_COLUMNS_ALIASES_CHECKS($tables);

  #generate code
    if(defined wantarray){
      return $class->generate_CODE($args);
    }
    else{
      $class->generate_CODE($args);
    }
    return;
}


sub dump_schema_at {
  my ($class, $args) = _get_obj_args(@_);

}

sub dump_class_at {

}

1;

__END__

=encoding utf8

=head1 NAME

DBIx::Simple::Class::Schema - Create and use classes representing tables from a database

=head1 SYNOPSIS

  #Somewhere in a utility script or startup() fo your application.
  DBIx::Simple::Class::Schema->dbix(DBIx::Simple->connect(...));
  my $perl_code = DBIx::Simple::Class::Schema->load_schema(
    namespace =>'My::Model',
    table => '%',              #all tables from the current database
    type  => "'TABLE','VIEW'", # make classes for tables and views
  );

  #Now eval() to use your classes.
  eval $perl_code || croak($@);

  #Or load and save it for more customisations and later usage.
  DBIx::Simple::Class::Schema->load_schema(
    namespace =>'My::Model',
    table => '%',              #all tables from the current database
    type  => "'TABLE','VIEW'", # make classes for tables and views
  );
  DBIx::Simple::Class::Schema->dump_schema_at(
    lib_root => "$ENV{HOME}/$ENV{PERL_LOCAL_LIB_ROOT}/lib"
    overwrite =>1 #overwrite existing files
  );


=head1 DESCRIPTION

DBIx::Simple::Class::Schema automates the creation of classes from
database tables. You can use it when you want to prototype quickly
your application. It is also very convenient as an initial generator and dumper of
your classes representing your database tables.

=head1 LICENSE AND COPYRIGHT

Copyright 2012 Красимир Беров (Krasimir Berov).

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

See http://dev.perl.org/licenses/ for more information.

