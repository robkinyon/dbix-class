# Synopsis #

The resultset is the most important concept in DBIx::Class. In many ways, it is
the foundational breakthrough behind the power of DBIx::Class. It is unique to
DBIC, but is frequently misunderstood.

This document explains what a resultset is, why you should care, and how you can
(ab)use resultsets for fun and profit.

# Notation #

Throughout this document, the following notations will be used:

* `$schema` is a DBIx::Class::Schema (or schema) object.
* `$source` is a DBIx::Class::ResultSource (or source) object.
* `$rs` is a DBIx::Class::ResultSet (or resultset) object. 
* `$row` is a DBIx::Class::Result (or resultset) object. 
* `My::Schema` is a generic schema class. It may have any classes necessary for
the examples.
* Artist and Album are the standard demo tables for DBIx::Class. These may have
any columns necessary for the examples.
* Col1 and Col2 are generic column names on any table. These may have any type
necessary for the examples.

# What is a resultset? #

First, what it is not. Unlike in most other ORMs, a resultset is **not** a
collection of rows that have been retrieved from the database. It is also not
the representation of a table in a database or a set of rows in a database.

A resultset, at its heart, is an object that knows how to generate SQL queries.
When you instantiate a resultset using `$schema->resultset('Artist')`, you have
an object that can generate the SQL.
```sql
SELECT me.col1, me.col2, ... FROM artists AS me
```

# The search() method #

This is not how the documentation normally describes the creation of resultsets.
Normally, you see something like:
```perl
my $rs = $schema->resultset('Artist')->search({
    col1 => 'A',
    col2 => 'B',
});
```

The implication is that the `$rs->search()` method is what isntantiates a
resultset.  This is only half true. The full truth is that both the
`$schema->resultset()` method is what initially *instantiates* a resultset. Its
resultset is a "full" resultset - if `$rs->all()` is called, it will return
every row from the table.

The `$rs->search()` method, on the other hand, returns another resultset object
with the additional search criteria applied. This does not affect the original
`$rs`. (In fact, none of the ResultSet instance methods affect the invocant.) It
also does not communicate with the database.

Both of these methods just create new objects. You can call these methods as
many times as you want with no performance penalty. It is often a good way to
organize your program by iteratively building up resultsets. We'll see some
examples of this later.

# Relationships and JOINs #

Tables (and other sources of data) are represented in DBIx::Class by
ResultSource objects. This resultsource is what you are definining when you call
the methods on `__PACKAGE__` in your Result class. Sources have relationships to
each other. The most common relationship is represented in the database by a
foreign key (FK) and is considered a parent-child relationship. The row in the
child table *belongs_to* a row in the parent table and the row in the parent
table row *has_many* rows in the child table.

For the rest of this section, let's assume Artist is a parent table for Album.
The most common relationship definitions would look something like:
```perl
# In Result/Artist.pm
__PACKAGE__->has_many( albums => 'My::Schema::Result::Album' => 'artist_id' );

# In Result/Album.pm
__PACKAGE__->belongs_to( artist => 'My::Schema::Result::Artist' => 'artist_id' );
```

## The object graph ##

The most common use of relationships is to walk the object graph. Once you have
a row in the parent `$artist`, you can say
```perl
my @albums = $artist->albums;
```

And, equivalently, when you have a row in the child `$album`, you can say
```perl
my $artist = $album->artist;
```

Both of those will do a query against the database when you invoke the methods.
(For how to avoid this, see the Prefetching section below.)

## JOINs ##

The relationship definitions also allow DBIx::Class to generate SQL queries that
have joins in them. For example, we may want to get all albums created by a
specific artist. We could do this:
```perl
my $artist = $schema->resultset('Artist')->search({
    name => 'Beethoven',
})->first;

my @albums= $artist->albums
```

Or, we could do this:
```perl
my @ablums = $schema->resultset('Album')->search({
    'artist.name' => 'Beethoven',
}, {
    join => 'artist',
})->all;
```

In this example, the difference isn't very large. But, imagine wanting to get a
list of all the albums from all artists whose hometown is in Austria and where
the name of the album's producer is 'Maury'. The query would look best like this
(assume the additional tables and relationships):
```perl
my @albums = $schema->resultset('Album')->search({
    'country.name' => 'Austria',
    'producer.name' => 'Maury',
}, {
    join => [
        artist => {
            hometown => country,
        },
        'producer',
    ],
})->all;
```

Reproducing that query by traversing the object graph would be very difficult to
write, impossible to maintain, and likely very very slow.

More on relationships and joins later.

## Examples of searching ##

# When does the query happen? #

DBIx::Class is lazy - it will only query the database when it absolutely has to.
Creating resultset objects doesn't communicate with the database. It is only
when you ask a resultset for a row object that it goes to the database.

When it does go to the database, it will get as much data as it knows it can get
in one call. So, it will retrieve all the columns in all the rows that match the
search criteria in the resultset.

Like everything else in DBIx::Class, you're able to modify this behavior. For
example, you can choose to specify which columns you want to retrieve. We'll see
how to do this later.

## Prefetching ##



# Useful extensions #

## DBIx::Class::Help::ResultSet::AutoRemoveColumns ##

This will prevent large columns (TEXT, BLOB, etc) from being retrieved by
default. You can add them into a specific search with `+columns`, if you need to
retrieve them.

**Note**: If you don't specify `+columns`, you will be unable to retrieve the
large columns later.
