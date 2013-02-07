package DBIx::Schema::DSL;
use 5.008_001;
use strict;
use warnings;

our $VERSION = '0.01';

use Mouse;
use SQL::Translator;
use SQL::Translator::Schema::Field;

has name => (
    is  => 'rw',
    isa => 'Str',
);

has db => (
    is  => 'rw',
    isa => 'Str',
    default => 'MySQL',
);

has translator => (
    is  => 'ro',
    isa => 'SQL::Translator',
    lazy => 1,
    default => sub {
        SQL::Translator->new;
    },
);

has schema => (
    is => 'ro',
    isa => 'SQL::Translator::Schema',
    lazy => 1,
    default => sub {
        my $self = shift;
        if (!$self->name || !$self->db) {
            die 'You should call `create_database` function beforehand.';
        }
        $self->translator->schema->name($self->name);
        $self->translator->schema->database($self->db);
        $self->translator->schema;
    },
);

has _creating_table => (
    is => 'rw',
    isa => 'HashRef',
    clearer => '_clear_creating_table',
);

has translate => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub {
        my $self = shift;
        $self->translator->translate(to => $self->db);
    },
);

no Mouse;

use Data::Validator;

{
    our $CONTEXT;
    sub context     { $CONTEXT  }
    sub set_context { $CONTEXT = $_[1] }
}

my @column_methods = grep {!CORE->can($_)} keys %SQL::Translator::Schema::Field::type_mapping;
my @export_methods = qw/create_database database create_table column unique pk auto_increment/;
sub import {
    my $caller = caller;

    no strict 'refs';
    for my $func (@export_methods, @column_methods) {
        *{"$caller\::$func"} = \&$func;
    }

    if ( $caller ne __PACKAGE__ ) {
        my @isa = @{"$caller\::ISA"};
        push @isa, __PACKAGE__;
        *{"$caller\::ISA"} = \@isa;
    }
}

sub new {bless {}, shift}

sub create_database($) {
    my $database_name = shift;

    my $kls = caller;
    $kls->set_context($kls->new) unless $kls->context;
    $kls->context->name($database_name);
}

sub database($) {
    my $database = shift;

    my $kls = caller;
    $kls->set_context($kls->new) unless $kls->context;
    $kls->context->db($database);
}

sub create_table($$) {
    my ($table_name, $code) = @_;

    my $kls = caller;
    my $c = $kls->context;

    $c->_creating_table({
        table_name => $table_name,
        columns     => [],
        constraints => {},
    });

    $code->();

    my $table = $c->schema->add_table(
        name   => $table_name,
        schema => $c,
    );
    for my $column (@{ $c->_creating_table->{columns} }) {
        $table->add_field(%{ $column } );
    }

    $c->_clear_creating_table;
}

sub column($$;%) {
    my ($column_name, $data_type, %opt) = @_;

    my $kls = caller;
    my $c = $kls->context;

    my $creating_data = $c->_creating_table
        or die q{can't call column method outside `create_table` method};

    my %args = (
        name      => $column_name,
        data_type => $data_type,
    );

    my %map = (
        null           => 'is_nullable',
        size           => 'size',
        default        => 'default_value',
        unique         => 'is_unique',
        pk             => 'is_primary_key',
        auto_increment => 'is_auto_increment',
    );
    for my $key (keys %map) {
        $args{$map{$key}}   = $opt{$key} if exists $opt{$key};
    }

    push @{$creating_data->{columns}}, \%args;
}

for my $method (@column_methods) {
    no strict 'refs';
    *{__PACKAGE__."::$method"} = sub {
        use strict 'refs';
        my $column_name = shift;

        column($column_name, $method, @_);
    };
}

for my $method (qw/unique pk auto_increment/) {
    no strict 'refs';
    *{__PACKAGE__."::$method"} = sub {
        use strict 'refs';
        ($method => 1);
    };
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
