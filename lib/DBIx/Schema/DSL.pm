package DBIx::Schema::DSL;
use 5.008_001;
use strict;
use warnings;

our $VERSION = '0.01';

use SQL::Translator::Schema::Constants;

{
    our $CONTEXT;
    sub context     { $CONTEXT ||= DBIx::Schema::DSL::Context->new }
}

# don't override CORE::int
my @column_methods = grep {!CORE->can($_)} keys(%SQL::Translator::Schema::Field::type_mapping), qw/tinyint string/;
my @column_sugars  = qw/pk unique auto_increment unsigned null/;
my @export_methods = qw/
    create_database     database    create_table    column  primary_key set_primary_key add_index add_unique_index
    foreign_key has_many has_one belongs_to context
/;
sub import {
    my $caller = caller;

    no strict 'refs';
    for my $func (@export_methods, @column_methods, @column_sugars) {
        *{"$caller\::$func"} = \&$func;
    }
}

sub create_database($) {
    my $database_name = shift;

    my $kls = caller;
    $kls->context->name($database_name);
}

sub database($) {
    my $database = shift;

    my $kls = caller;
    $kls->context->db($database);
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
        pk             => 'is_primary_key',
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
    my $column_name = shift;
    column($column_name, 'integer', pk(), auto_increment(), @_);
}

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
    *{__PACKAGE__."::$method"} = sub {
        use strict 'refs';
        ($method => 1);
    };
}

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
        type   => 'UNIQUE',
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

package DBIx::Schema::DSL::Context;

use Moo;
use SQL::Translator;
use SQL::Translator::Schema::Field;

has name => (
    is  => 'rw',
);

has db => (
    is  => 'rw',
    default => sub {'MySQL'},
);

has translator => (
    is  => 'lazy',
    default => sub {
        SQL::Translator->new;
    },
);

has schema => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        $self->translator->schema->name($self->name);
        $self->translator->schema->database($self->db);
        $self->translator->schema;
    },
);

has _creating_table => (
    is => 'rw',
    clearer => '_clear_creating_table',
);

has translate => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $output = $self->translator->translate(to => $self->db);
        # ignore initial comments.
        1 while $output =~ s/\A--.*?\r?\n//ms;
        $output;
    },
);

no Moo;

sub _creating_table_name {
    shift->_creating_table->{table_name}
        or die 'Not in create_table block.';
}

1;
__END__

=head1 NAME

DBIx::Schema::DSL - Perl extention to do something

=head1 VERSION

This document describes DBIx::Schema::DSL version 0.01.

=head1 SYNOPSIS

    use parent 'DBIx::Schema::DSL';

    create_table user => sub {
        column  'id', 'integer';
        integer 'age', default => 0;
        varchar 'name', default => '', size => 255, null => 0;
        text    'detail', default => 'ok';
        datetime 'created_at';
        date     'last_login_date';

        add_index        hoge => [qw/hoge fuga/];
        add_index        hoge => [qw/hoge fuga/];
        add_unique_index fuga => [qw/id updated_at/];

        set_primary_key 'id', 'created_at';

        add_options({
            ENGINE          => 'InnoDB',
            'CHARACTER SET' => 'utf8',
        });
    };

=head1 DESCRIPTION

# TODO

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
