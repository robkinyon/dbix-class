# Synopsis #

Generating useful test data for applications is hard. The standard practices all
suck. The DBIx::Class extension DBIx::Class::Sims (aka Sims) provides a much
better solution.

# The Problem #

There are a few constants when developing applications that use databases
(whether for the web or not).

1. Your application's interactions with your database are complicated.
1. Your database schema is going to change. Often.
1. You, the developer, aren't going to be aware of much of the earlier points.

The quicker everything changes, the more you want tests. Lots and lots of tests.
But, of course, the quicker everything changes, the harder it becomes to write
tests against the database.

# Fixtures - the solution that hurts #

The obvious solution to solve this conundrum is something called *fixtures*. 
Fixtures are a snaphot in time of the data you intend to use. You build up the
data as you need and take a dump of it (using some tool such as to mydumper or
DBIx::Class::Fixtures). When you run your tests, you would drop and recreate the
database, load the snapshot into the database, then run your test.

At first, this works so well. You can even take the snapshot from production to
reproduce bugs reported by users and build your regression test suite.

## Where things go wrong ##

Fixtures address problem #1 ("Things are complicated") quite nicely. But, they
fail horribly when confronted with problem #2 ("Everything changes"). At first,
it's just one of the table your unit test is concerned with. A new column is
added that doesn't have a default value or an existing column changes type and
the old values no longer work. So, you shrug and modify the fixtures so that the
tests pass again.

Then, the first domino falls. You're working on a page in the admin section and
you add a required column to the users table. The admin section tests run clean,
so you submit your changeset for code review, it passes, and heads to Jenkins
for continuous integration. Proud of yourself, you head to lunch, only to return
to find 70% of tests are now failing. It turns out that the users table is a
parent for several of the key tables and now all the fixtures for all the tests
are broken.

Now, you're stuck with a "Problem"(tm). There are several dozen fixtures in use
across the 400+ tests in your test suite. Do you:

A. Take the 3 days to rework all the fixtures by hand?
A. Take the 3 days to build a tool to migrate all the fixtures?
   * Note this will require user input to pick the right value in some cases.
A. Consolidate the fixtures into 3 different scenarios?
A. Skip the tests?

Most teams end up choosing option D. If your team is really disciplined, you may
end up with options B or C. No-one does option A, even though that's what I keep
hearing whenever I bring up this problem.

And this is just adding a column in one table. What happens if the change is to
add a new table or to refactor a large chunk of tables?

## The root of the issue ##

The real problem with fixtures for tests is that it requires the test to know
about parts of the system that aren't under test. For example, if your test is
focused on the interaction of invoices and lineitems when doing returns, why
should adding a column to the users table affect this? If you're using fixtures,
it's because invoices has a FK to sales which has a FK (buyer\_id) to users.
Since those are non-NULL'able foreign keys, we have to have a value, *even
though that row makes no difference to the test*. Yes, for some tests of the
return logic, it might matter, but not for *this* test.

Instead of hard-coding all of the dependencies, the application should be able
to figure all of that out at runtime, especially if I tell it everything it
needs to know.

# The real solution #

If we use an ORM, such as DBIx::Class, we have already provided our application
with all the information it needs to create the necessary rows.

# Author #

Rob Kinyon <rob.kinyon@gmail.com> is a long-time developer and contributor to
both CPAN and DBIx::Class. He's written several articles on perl.com and can be
found at http://robonperl.blogspot.com/, @rkinyon on Twitter, and robkinyon on
IRC.
