# Synopsis #

The resultset is the most important concept in DBIx::Class. In many ways, it is
the foundational breakthrough behind the power of DBIx::Class. It is unique to
DBIC, but is frequently misunderstood.

This document explains what a resultset is, why you should care, and how you can
(ab)use resultsets for fun and profit.

# Notation #

Throughout this document, the following notations will be used:

* `$schema` is a DBIx::Class::Schema (or schema) object.
* `$rs` is a DBIx::Class::ResultSet (or resultset) object. 
* `$row` is a DBIx::Class::Result (or resultset) object. 
* Foo and Bar are generic table names. These may have any columns necessary for
the examples.
* Col1 and Col2 are generic column names on any table. These may have any type
necessary for the examples.

# What is a resultset? #

First, what it is not. Unlike in most other ORMs, a resultset is **not** a
collection of rows that have been retrieved from the database.

A resultset, at its heart, is an object that represents an SQL query. When you
create a resultset using `$schema->resultset('Foo')`, you create an object that
represents the query `SELECT me.col1, me.col2, ... FROM foo AS me`. 

## The search() method ##

This is not how the documentation normally describes the creation of resultsets.
Normally, you see something like:
```perl
my $rs = $schema->resultset('Foo')->search({
    col1 => 'A',
    col2 => 'B',
});
```

The implication is that the `$rs->search()` method is what creates a resultset.
This is only half true. The full truth is that both the `$schema->resultset()`
method is what initially *creates* a resultset. Its resultset is a "full"
resultset - if `$rs->all()` is called, it will return every row from the table.

The `$rs->search()` method, on the other hand, returns another resultset object
with the additional search criteria applied. This does not affect the original
`$rs`. (In fact, none of the ResultSet instance methods affect the invocant.) It
also does not communicate with the database.

Both of these methods just create new objects. You can call these methods as
many times as you want with no performance penalty. It is often a good way to
organize your program by iteratively building up resultsets. We'll see some
examples of this later.

# When does the query happen? #

DBIx::Class is lazy - it will only query the database when it absolutely has to.
Creating resultset objects doesn't communicate with the database. It is only
when you ask a resultset for a row object that it goes to the database.

When it does go to the database, it will get as much data as it knows it can get
in one call. So, it will retrieve all the 
