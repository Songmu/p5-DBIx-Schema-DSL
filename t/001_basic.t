#!perl -w
use strict;
use Test::More;

package Hoge;
use DBIx::Schema::DSL;

package main;

my $hoge = Hoge->new;
ok $hoge;

ok $hoge->can('context');
ok $hoge->can('name');

done_testing;
