# README

This README would normally document whatever steps are necessary to get the
application up and running.

## Requirements

* Ruby 3.3.4
* PostgreSQL 12+ (the application's only supported database)

## Database setup

The application uses **PostgreSQL** in all environments. No other database is
supported.

### Configuration

Database connection settings are read from environment variables:

| Variable            | Default                         | Description                          |
|---------------------|---------------------------------|--------------------------------------|
| `DATABASE_URL`      | –                               | Optional full connection URL. When set, it overrides everything below |
| `DATABASE_HOST`     | `127.0.0.1`                     | Database host                        |
| `DATABASE_PORT`     | `5432`                          | Database port                        |
| `DATABASE_USERNAME` | current OS user (`USER`)        | Database role                        |
| `DATABASE_PASSWORD` | (empty)                         | Database password                    |
| `DATABASE_NAME`     | `expense_tracker_production`    | Production database name             |

Example using a connection URL:

```sh
export DATABASE_URL="postgres://myuser:mypassword@localhost:5432/expense_tracker_development"
```

### Create and initialize a fresh database

```sh
bin/rails db:setup
```

`db:setup` creates the database, runs all migrations, and loads the seed data
required for a fresh installation (default expense and income categories).

Existing databases can be migrated and seeded individually:

```sh
bin/rails db:migrate   # run pending migrations
bin/rails db:seed      # load default categories (idempotent, safe to re-run)
```

To fully reset a database:

```sh
bin/rails db:reset     # drop, create, migrate, and seed
```

### Running the test suite

```sh
bin/rails test
```

The test suite runs against the PostgreSQL `test` database and is recreated
automatically between runs.

### Background jobs

Jobs (e.g., the Gmail recurring sync) run through [Solid
Queue](https://github.com/rails/solid_queue) using the primary database. Start
a worker with:

```sh
bin/rails solid_queue:start
```
