FROM ruby:3

WORKDIR /opt/app
COPY Gemfile* .
RUN bundle install
COPY . .
CMD ["bundle", "exec", "ruby", "app.rb", "-o", "0.0.0.0"]
EXPOSE 4567
