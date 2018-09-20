# frozen_string_literal: true

require "spec_helper"

RSpec.describe Kafka::Librato do
  it "has a version number" do
    expect(Kafka::Librato::VERSION).not_to be nil
  end
end
