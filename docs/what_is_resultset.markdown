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

A resultset, at its heart, is a (mostly) immutable object that knows how to
generate SQL queries. When you instantiate a resultset using
`$schema->resultset('Artist')`, you have an object that can generate the SQL.
```sql
SELECT me.col1, me.col2, ... FROM artists AS me
```

**Note**: The resultset isn't the SQL query - it's a query generator. This is
how new resultsets can be made from old ones.

# The search() method #

This is how the documentation normally describes the use of resultsets.
Normally, you see something like:
```perl
my $rs = $schema->resultset('Artist')->search({
    col1 => 'A',
    col2 => 'B',
});
```

The implication is that the `$rs->search()` method is what instantiates a
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

## Walking the object graph ##

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
(For how to avoid this additional query, see the Prefetching section below.)

## Walking JOINs ##

The relationship definitions also allow DBIx::Class to generate SQL queries that
have joins in them. For example, we may want to get all albums created by a
specific artist. We could do this:
```perl
my $artist = $schema->resultset('Artist')->search({
    name => 'Beethoven',
})->first;

my @albums= $artist->albums;
```
And that would work just fine. But, it's cumbersome and doesn't really describe
exactly what we're trying to accomplish.

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

# Searching #

In the documentation for `$rs->search()`, there are two parameters. The first
parameter corresponds to the WHERE clause. It is a data structure which is
handed off to SQL::Abstract for processing. In most cases, that's all you're
ever going to need. And, for the most part, that's what most ORMs will provide
for you. Well over 70% of the queries I've ever written with DBIx::Class only
use the first parameter.

## The WHERE clause ##

SQL::Abstract is a very powerful tool to build maintainable complex WHERE
clauses. A full discussion of its power is beyond this article, but here is an
example that could give you some ideas.
```perl
$artist_rs->search([
    name => [ 'Joe', 'Tim' ],
    {
        'producer.name' => { '!=' => 'Maury' },
        'producer.salary' => { '>=' => 100_000 },
        -and => [
            'first_album' => '2000',
            'last_album' => '2005',
        ],
    },
], {
    join => 'producer',
});
```
This translates to:
```sql
SELECT <columns>
FROM artist AS me
JOIN producer AS producer ON (artist.producer_id = producer.id)
WHERE me.name IN ( ?, ? )
OR (
    ( producer.name != ? AND producer.salary >= ? )
    AND
    ( first_album = ? OR last_album = ? )
)
```
With bind parameters of `'Joe', 'Tim', 'Maury', 100000, 2000, 2005`

A few things to note:
* The first parameter doesn't have to be a hashref. It can be an arrayref if
you want to OR clauses together.
* You can nest and chain AND and OR clauses together very easily.
* Operators can be specified, as can IN clauses.
* DBIx::Class passes all your values as bind parameters.
   * Where possible, it passes them in as the proper type, not just strings.

## The rest ##

The second parameter is where a lot of the magic happens. We've already seen it
in action to specify joins through relationships. You can also use it to
specify (among other things):

1. Limits and offsets
1. Which columns to retrieve.
   * Only retrieve the columns you need.
   * Retrieve a few columns from several other tables as well.
1. Ordering and grouping
1. Having clauses
1. Prefetching related rows. (More in the Prefetching section below)
1. Caching
   * This is useful only if you reuse a specific `$rs` object. It does **NOT**
   provide process-wide caching.

Some of these options have database-specific actions. For example, there is no
standard SQL extension for limits and offsets, so every database vendor has
developed there own. DBIx::Class works very hard to make sure the right flavor
of SQL is used for the database you've connected to.

Read through the documentation for DBIx::Class::ResultSet in the ATTRIBUTES for
more information on each one of these options (and more).

# Retrieving your rows #

So far, we've talked about how to create the perfect SQL 

## When does the query actually happen? ##

DBIx::Class is lazy - it will only query the database when it absolutely has to.
Creating resultset objects doesn't communicate with the database. It is only
when you ask a resultset for a row object that it goes to the database.

When it does go to the database, it will get as much data as it knows it can get
in one call. So, it will retrieve all the columns in all the rows that match the
search criteria in the resultset.

Like everything else in DBIx::Class, you're able to modify this behavior. For
example, you can choose to specify which columns you want to retrieve in the
second parameter to `$rs->search()`.

## Prefetching ##

A very common use case is to retrieve a set of rows, then iterate over them and
all of the rows of some has_many relationship. Something like:
```perl
my $artists_rs = $schema->resultset('artist')->search({
    first_album_year => 2000,
});

foreach my $artist ( $artists_rs->all ) {
    print "Artist: " . $artist->name . "\n";
    foreach my $album ( $artist->albums ) {
        print "    Album: " . $album->name . "\n";
    }
}
```

In the normal case (and what most other ORMs do), this would require 1+N SQL
queries. 1 for the query of the `artists` table and N for the N queries of the
`albums` table (where N i the number of artists).

DBIx::Class, of course, has a better solution. If we modify the query to be:
```perl
my $artists_rs = $schema->resultset('artist')->search({
    first_album_year => 2000,
}, {
    prefetch => 'albums',
});
```
Then, all the albums will be fetched as part of the first query. This collapses
our 1+N queries into a single (very large) query. This first query will take a
little more time and uses up extra memory, but the overall runtime is reduced
quite significantly.

**NOTE**: prefetch should be treated as an *optimization* to be used only when
absolutely necessary. It should not be treated as a synonym for "join", even
though it currently behaves as one with respect to connecting tables. Remember -
this returns all the connecting rows. So, use it sparingly.

## HashRefInflator (HRI) ##

A common use for pulling data out of a database is to display it in a page of
some kind, usually by using a template to put things together. If we take our
prefetch example above, we might have the following Template Toolkit template:
```
[% FOR artist IN artists -%]
Name: [% artist.name %]
    [%- FOR album IN artist.albums %]
    Album: [% album.name %]
    [%- END %]
[%- END %]
```
and we could call it as so:
```perl
my $artists_rs = $schema->resultset('artist')->search({
    first_album_year => 2000,
}, {
    prefetch => 'albums',
});

my $vars = {
    artists => [ $artist_rs->all ],
};
$tt->process( $template_name, $vars );
```

The problem here is that the template code can now modify our database. So, if
our template looked like:
```
[% FOR artist IN artists -%]
    [% artist.delete %]
[%- END %]
```
That would be a "Problem"(tm).

DBIx::Class, again, has a solution.
```
my $artists_rs = $schema->resultset('artist')->search({
    first_album_year => 2000,
}, {
    prefetch => 'albums',
    result_class => 'DBIx::Class::ResultClass::HashRefInflator',
});

# The rest same as before
```
Now, instead of being provided an array of My::Schema::Result::Artist objects,
the template receives an array of hashrefs containing the data of each artist.
The template can no longer interact with the database, even by mistake.

**NOTE**: This is also a performance boost, sometimes up to 50% faster. However,
you should not sprinkle HRI all over your codebase willy-nilly. The code becomes
harder to maintain and, honestly, the performance boost is usually on the order
of 1-2%. The cost of creating objects vs. hashrefs just isn't that high.

# Extending the ResultSet #

# Relationships #

# Useful extensions #

## DBIx::Class::Help::ResultSet::AutoRemoveColumns ##

This will prevent large columns (TEXT, BLOB, etc) from being retrieved by
default. You can add them into a specific search with `+columns`, if you need to
retrieve them.

**Note**: If you don't specify `+columns`, you will be unable to retrieve the
large columns later.
