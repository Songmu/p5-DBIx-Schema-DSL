package DBIx::Schema::DSL;
use 5.008_001;
use strict;
use warnings;

our $VERSION = '0.01';

use DBIx::Schema::DSL::Context;
use SQL::Translator::Schema::Constants;
use SQL::Translator::Schema::Field;

sub context {
    my $pkg = shift;
    die 'something wrong when calling context method.' if $pkg eq __PACKAGE__;
    no strict 'refs';
    ${"$pkg\::CONTEXT"} ||= DBIx::Schema::DSL::Context->new;
}

# don't override CORE::int
my @column_methods =
    grep {!CORE->can($_) && !main->can($_)} keys(%SQL::Translator::Schema::Field::type_mapping), qw/tinyint string number/;
my @column_sugars  = qw/unique auto_increment unsigned null/;
my @rev_column_sugars = qw/not_null signed/;
my @export_dsls = qw/
    create_database database    create_table    column      primary_key set_primary_key add_index   add_unique_index
    foreign_key     has_many    has_one         belongs_to  add_table_options   default_unsigned    columns pk  fk
/;
my @class_methods = qw/context output translate_to translator/;
sub import {
    my $caller = caller;

    no strict 'refs';
    for my $func (@export_dsls, @column_methods, @column_sugars, @class_methods, @rev_column_sugars) {
        *{"$caller\::$func"} = \&$func;
    }
}

sub create_database($) { caller->context->name(shift) }
sub database($)        { caller->context->db(shift)   }

sub add_table_options {
    my $c = caller->context;
    my %opt = @_;

    $c->set_table_extra({
        %{$c->table_extra},
        %opt,
    });
}

sub default_unsigned() {
    caller->context->default_unsigned(1);
}

sub create_table($$) {
    my ($table_name, $code) = @_;

    my $kls = caller;
    my $c = $kls->context;

    $c->_creating_table({
        table_name  => $table_name,
        columns     => [],
        indices     => [],
        constraints => [],
        primary_key => undef,
    });

    $code->();

    my $data = $c->_creating_table;
    my $table = $c->schema->add_table(
        name   => $table_name,
        extra  => {%{$c->table_extra}},
    );
    for my $column (@{ $data->{columns} }) {
        $table->add_field(%{ $column } );
    }
    for my $index (@{ $data->{indices} }) {
        $table->add_index(%{ $index } );
    }
    for my $constraint (@{ $data->{constraints} }) {
        $table->add_constraint(%{ $constraint } );
    }
    $table->primary_key($data->{primary_key}) if $data->{primary_key};

    $c->_clear_creating_table;
}
sub columns(&) {shift}

sub column($$;%) {
    my ($column_name, $data_type, %opt) = @_;
    $data_type = 'varchar' if $data_type eq 'string';

    my $c = caller->context;

    my $creating_data = $c->_creating_table
        or die q{can't call `column` method outside `create_table` method};

    my %args = (
        name      => $column_name,
        data_type => uc $data_type,
    );

    my %map = (
        null           => 'is_nullable',
        size           => 'size',
        limit          => 'size',
        default        => 'default_value',
        unique         => 'is_unique',
        primary_key    => 'is_primary_key',
        auto_increment => 'is_auto_increment',
    );
    for my $key (keys %map) {
        $args{$map{$key}}   = delete $opt{$key} if exists $opt{$key};
    }
    %args = (
        %args,
        %opt
    );
    if (exists $args{unsigned}) {
        my $extra = $args{extra} || {};
        $extra->{unsigned} = delete $args{unsigned};
        $args{extra} = $extra;
    }
    elsif ($c->default_unsigned && $data_type =~ /int(?:eger)$/) {
        $args{extra}{unsigned} = 1;
    }

    if ($args{precision}) {
        my $precision = delete $args{precision};
        my $scale     = delete $args{scale} || 0;
        $args{size} = [$precision, $scale];
    }

    if ($args{is_primary_key}) {
        $creating_data->{primary_key} = $column_name;
    }
    elsif ($args{is_unique}) {
        push @{$creating_data->{constraints}}, {
            name   => "${column_name}_uniq",
            fields => [$column_name],
            type   => UNIQUE,
        };
    }

    push @{$creating_data->{columns}}, \%args;
}

sub primary_key {
    if (defined wantarray) {
        (primary_key => 1);
    }
    else { # void context
        my $column_name = shift;

        @_ = ($column_name, 'integer', primary_key(), auto_increment(), @_);
        goto \&column;
    }
}
*pk = \&primary_key;

for my $method (@column_methods) {
    no strict 'refs';
    *{__PACKAGE__."::$method"} = sub {
        use strict 'refs';
        my $column_name = shift;

        @_ = ($column_name, $method, @_);
        goto \&column;
    };
}

for my $method (@column_sugars) {
    no strict 'refs';
    *{__PACKAGE__."::$method"} = sub() {
        use strict 'refs';
        ($method => 1);
    };
}
sub not_null() { (null => 0)     }
sub signed()   { (unsigned => 0) }

sub set_primary_key(@) {
    my @keys = @_;

    my $c = caller->context;

    my $creating_data = $c->_creating_table
        or die q{can't call `set_primary_key` method outside `create_table` method};

    $creating_data->{primary_key} = \@keys;
}

sub add_index {
    my $c = caller->context;

    my $creating_data = $c->_creating_table
        or die q{can't call `add_index` method outside `create_table` method};

    my ($idx_name, $fields, $type) = @_;

    push @{$creating_data->{indices}}, {
        name   => $idx_name,
        fields => $fields,
        ($type ? (type => $type) : ()),
    };
}

sub add_unique_index {
    my $c = caller->context;

    my $creating_data = $c->_creating_table
        or die q{can't call `add_unique_index` method outside `create_table` method};

    my ($idx_name, $fields) = @_;

    push @{$creating_data->{indices}}, {
        name   => $idx_name,
        fields => $fields,
        type   => UNIQUE,
    };
}

sub foreign_key {
    my $c = caller->context;

    my $creating_data = $c->_creating_table
        or die q{can't call `foreign` method outside `create_table` method};

    my ($columns, $table, $foreign_columns) = @_;

    push @{$creating_data->{constraints}}, {
        type => FOREIGN_KEY,
        fields           => $columns,
        reference_table  => $table,
        reference_fields => $foreign_columns,
    };
}
*fk = \&foreign_key;

sub has_many {
    my $c = caller->context;

    my ($table, %opt) = @_;

    my $columns         = $opt{column}         || 'id';
    my $foreign_columns = $opt{foregin_column} || $c->_creating_table_name .'_id';

    @_ = ($columns, $table, $foreign_columns);
    goto \&foreign_key;
}

sub has_one {
    my $c = caller->context;

    my ($table, %opt) = @_;

    my $columns         = $opt{column}         || 'id';
    my $foreign_columns = $opt{foregin_column} || $c->_creating_table_name .'_id';

    @_ = ($columns, $table, $foreign_columns);
    goto \&foreign_key;
}

sub belongs_to {
    my ($table, %opt) = @_;

    my $columns         = $opt{column}         || "${table}_id";
    my $foreign_columns = $opt{foregin_column} || 'id';

    @_ = ($columns, $table, $foreign_columns);
    goto \&foreign_key;
}

sub output {
    shift->context->translate;
}

sub translator {
    shift->context->translator;
}

sub translate_to {
    my ($kls, $db_type) = @_;

    $kls->translator->translate(to => $db_type);
}

1;
__END__

=head1 NAME

DBIx::Schema::DSL - Perl extention to declear database schema like ActiveRecord::Schema

=head1 VERSION

This document describes DBIx::Schema::DSL version 0.01.

=head1 SYNOPSIS

declaration

    package My::Schema;
    use DBIx::Schema::DSL;

    database 'MySQL';
    create_database 'my_database';

    add_table_options
        mysql_table_type => 'InnoDB',
        mysql_charset    => 'utf8';

    create_table 'book' => columns {
        integer 'id',   primary_key, auto_increment;
        varchar 'name', null;
        integer 'author_id';
        decimal 'price', 'size' => [4,2];

        belongs_to 'author';
    };

    create_table 'author' => columns {
        primary_key 'id';
        varchar 'name';
        decimal 'height', 'precision' => 4, 'scale' => 1;

        has_many 'book';
    };

    1;

using

    use My::Schema;
    print My::Schema->output; # output DDL

=head1 DESCRIPTION

# TODO

B<THE SOFTWARE IS IT'S IN ALPHA QUALITY. IT MAY CHANGE THE API WITHOUT NOTICE.>

=head1 INTERFACE

=head2 Functions

=head3 C<< hello() >>

# TODO

=head1 DEPENDENCIES

Perl 5.8.1 or later.

=head1 BUGS

All complex software has bugs lurking in it, and this module is no
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 SEE ALSO

L<perl>

=head1 AUTHOR

Masayuki Matsuki E<lt>y.songmu@gmail.comE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2013, Masayuki Matsuki. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
