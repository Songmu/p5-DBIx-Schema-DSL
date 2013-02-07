use strict;
use warnings;
use utf8;
use Test::More;

package Hoge;
use DBIx::Schema::DSL;

database 'MySQL';
create_database 'test';

create_table user => sub {
    integer 'id',   pk => 1, auto_increment => 1;
    integer 'member_id', unique;
    column  'gender', 'tinyint', null => 1;
    integer 'age', limit => 1, unsigned => 0, null;
    varchar 'name', null => 0;
    varchar 'description', null => 1;
    text    'profile';
};

create_table book => sub {
    integer 'id',   pk, auto_increment;
    varchar 'name', null => 0;
    integer 'author_id';
    decimal 'price', size => [4,2];
};

create_table author => sub {
    primary_key 'id';
    varchar 'name';
    decimal 'height', precision => 4, scale => 1;
};

package main;

my $c = Hoge->context;

isa_ok $c, 'DBIx::Schema::DSL';
isa_ok $c, 'Hoge';
is $c->name, 'test';
is $c->db, 'MySQL';

isa_ok $c->translator, 'SQL::Translator';
isa_ok $c->schema,     'SQL::Translator::Schema';

ok $c->translate and note $c->translate;

done_testing;
