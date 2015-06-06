[![Code Climate](https://codeclimate.com/github/openfoodfoundation/openfoodnetwork.png)](https://codeclimate.com/github/openfoodfoundation/openfoodnetwork)

# Open Food Network

The Open Food Network is an online marketplace for local food. It enables a network of independent online food stores that connect farmers and food hubs (including coops, online farmers' markets, independent food businesses etc);  with individuals and local businesses. It gives farmers and food hubs an easier and fairer way to distribute their food.

Supported by the Open Food Foundation, we are proudly open source and not-for-profit - we're trying to seriously disrupt the concentration of power in global agri-food systems, and we need as many smart people working together on this as possible.

We're part of global movement - get involved!

* Fill in this short survey to tell us who you are and what you want to do with OFN: https://docs.google.com/a/eaterprises.com.au/forms/d/1zxR5vSiU9CigJ9cEaC8-eJLgYid8CR8er7PPH9Mc-30/edit#
* Find out more and join in the conversation - http://openfoodnetwork.org


## Dependencies

* Rails 3.2.x
* Ruby >= 1.9.3
* PostgreSQL database
* PhantomJS (for testing)
* See Gemfile for a list of gems required


## Get it

The source code is managed with Git (a version control system) and
hosted at GitHub.

You can view the code at:

    https://github.com/openfoodfoundation/openfoodnetwork

You can download the source with the command:

    git clone git@github.com:openfoodfoundation/openfoodnetwork


## Get it running

For those new to Rails, the following tutorial will help get you up to speed with configuring a Rails environment: http://guides.rubyonrails.org/getting_started.html .

First, check your dependencies: Ensure that you have Ruby 1.9.x installed:

    ruby --version

Install the project's gem dependencies:

    bundle update
    bundle install

Bundle update was required to avoid an error installing libv8 (Mac OSX 10.10.2)

Configure the site:

    cp config/application.yml.example config/application.yml
    edit config/application.yml

Create the development and test databases, using the settings specified in `config/database.yml`, and populate them with a schema and seed data:

    rake db:setup

Commented out this line in config/enterprise.rb as no longer required in latest version
acts_as_gmappable :process_geocoding => false

Failed with: 
NoMethodError: undefined method `preview_path=' for ActionMailer::Base:Class
/Users/spettitt/apps/openfoodnetwork/app/mailers/spree/base_mailer_decorator.rb:1:in `<top (required)>'
Can't find source of this - commented out whole base_mailer_decorator.rb file (and other *_mailer_decorator.rb files)

Load some default data for your environment:

    rake openfoodnetwork:dev:load_sample_data

At long last, your dreams of spinning up a development server can be realised:

    rails server


## Testing

Tests, both unit and integration, are based on RSpec. To run the test suite, first prepare the test database:

    bundle exec rake db:test:prepare

Then the tests can be run with:

    bundle exec rspec spec

The site is configured to use
[Zeus](https://github.com/burke/zeus) to reduce the pre-test
startup time while Rails loads. See the Zeus github page for
usage instructions.


## Credits

* Andrew Spinks (http://github.com/andrewspinks)
* Rohan Mitchell (http://github.com/rohanm)
* Rob Harrington (http://github.com/oeoeaio)
* Alex Serdyuk (http://github.com/alexs333)
* David Cook (http://github.com/dacook)
* Will Marshall (http://soundcloud.com/willmarshall)
* Laura Summers (https://github.com/summerscope)
* Maikel Linke (https://github.com/mkllnk)

## Licence

Copyright (c) 2012 - 2015 Open Food Foundation, released under the AGPL licence.
