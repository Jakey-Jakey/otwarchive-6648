# Repository Guidelines for Agents

This repository contains the code for the OTW-Archive Ruby on Rails application. Please read these guidelines carefully before making any changes.

## Setup

1. Install Ruby (target version 3.1) and [Bundler](https://bundler.io/).
2. Run `bin/setup` to install dependencies and set up the database.
3. If you need to reset your development or test database, run `./script/reset_database.sh` with the appropriate `RAILS_ENV`.

## Testing

- **RSpec**: run `bundle exec rspec` to execute unit tests found in the `spec/` directory.
- **Cucumber**: run `bundle exec cucumber` to execute feature tests in the `features/` directory.
- **RuboCop**: run `bundle exec rubocop` to check code style using the rules defined in `.rubocop.yml`.

Always run the RuboCop and RSpec suites before committing changes. Feature tests are optional unless you modify the corresponding Cucumber features.

## Commit Messages

Use concise commit messages that clearly describe the change. Avoid large, multi-purpose commits whenever possible.

## Branches

All work should be done on a separate branch and merged into `master` via pull request.

## Contact

For questions, please contact the maintainers at [otw-coders@transformativeworks.org](mailto:otw-coders@transformativeworks.org).
