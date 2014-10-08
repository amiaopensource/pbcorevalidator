# PBCore Validator, Validator class
# Copyright © 2009 Roasted Vermicelli, LLC
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'libxml'

# A class to validate PBCore documents.
class Validator
  include LibXML #:nodoc:

  # The PBCore namespace
  DC_NAMESPACE = "http://purl.org/dc/elements/1.1/"

  # List of supported XSDs
  DC_VERSIONS = {
#    "1.1" => { :version => "PBCore 1.1", :xsd => "PBCoreXSD_Ver_1-1_Final.xsd" },
    "DC" => { :version => "DublinCore", :xsd => "dc.xsd" },
    "Simple" => { :version => "Simple DC", :xsd => "simple_dc.xsd" },
    "1.2.1" => { :version => "PBCore 1.2.1", :xsd => "PBCoreXSD_Ver_1-2-1.xsd" },
    "1.3" => { :version => "PBCore 1.3", :xsd => "PBCoreXSD-v1.3.xsd" }
  }.freeze

  # returns the LibXML::XML::Schema object of the PBCore schema
  def self.schema(dc_version)
    @@schemas ||= {}
    @@schemas[dc_version] ||= XML::Schema.document(XML::Document.file(File.join(File.dirname(__FILE__), "..", "data", DC_VERSIONS[dc_version][:xsd])))
  end

  # creates a new PBCore validator object, parsing the provided XML.
  #
  # io_or_document can either be an IO object or a String containing an XML document.
  def initialize(io_or_document, dc_version = "DublinCore")
    XML.default_line_numbers = true
    @errors = []
    @dc_version = dc_version
    set_rxml_error do
      @xml = io_or_document.respond_to?(:read) ?
        XML::Document.io(io_or_document) :
        XML::Document.string(io_or_document)
    end
  end

  # checks the PBCore document against the XSD schema
  def checkschema
    return if @schema_checked || @xml.nil?

    @schema_checked = true
    set_rxml_error do
      @xml.validate_schema(Validator.schema(@dc_version))
    end
  end

  # check for things which are not errors, exactly, but which are not really good ideas either.
  #
  # this is subjective, of course.

  # returns true iff the document is perfectly okay
  def valid?
    checkschema
    @errors.empty?
  end

  # returns true iff the document is at least some valid form of XML
  def valid_xml?
    !(@xml.nil?)
  end

  # returns a list of perceived errors with the document.
  def errors
    checkschema
    @errors.clone
  end

  protected
  # Runs some code with our own LibXML error handler, which will record
  # any seen errors for later retrieval.
  #
  # If no block is given, then our error handler will be installed but the
  # caller is responsible for resetting things when done.
  def set_rxml_error
    XML::Error.set_handler{|err| self.rxml_error(err)}
    if block_given?
      begin
        yield
      rescue XML::Error
        # we don't have to do anything, because LibXML throws exceptions after
        # already passing them to the selected handler. kind of strange.
      end
      XML::Error.reset_handler
    end
  end

  def rxml_error(err) #:nodoc:
    @errors << err
  end

  private
  def check_picklist(elt, picklist)
    each_elt(elt) do |node|
      if node.content.strip.empty?
        @errors << "#{elt} on #{node.line_num} is empty. Perhaps consider leaving that element out instead."
      elsif !picklist.any?{|i| i.downcase == node.content.downcase}
        @errors << "“#{node.content}” on line #{node.line_num} is not in the PBCore suggested picklist value for #{elt}."
      end
    end
    check_lists(elt)
  end

  def check_lists(elt)
    each_elt(elt) do |node|
      if node.content =~ /[,|;]/
        @errors << "In #{elt} on line #{node.line_num}, you have entered “#{node.content}”, which looks like it may be a list. It is preferred instead to repeat the containing element."
      end
    end
  end

  # look for "Mike Castleman" and remind the user to say "Castleman, Mike" instead.
  def check_names(elt)
    each_elt(elt) do |node|
      if node.content =~ /^(\w+\.?(\s\w+\.?)?)\s+(\w+)$/
        @errors << "It looks like the #{elt} “#{node.content}” on line #{node.line_num} might be a person's name. If it is, then it is preferred to have it like “#{$3}, #{$1}”."
      end
    end
  end

  # ensure that no single instantiation has both a formatDigital and a formatPhysical
  def check_only_one_format
    each_elt("pbcoreInstantiation") do |node|
      if node.find(".//pbcore:formatDigital", "pbcore:#{PBCORE_NAMESPACE}").size > 0 &&
          node.find(".//pbcore:formatPhysical", "pbcore:#{PBCORE_NAMESPACE}").size > 0
        @errors << "It looks like the instantiation on line #{node.line_num} contains both a formatDigital and a formatPhysical element. This is probably not what you intended."
      end
    end
  end

  def each_elt(elt)
    @xml.find("//pbcore:#{elt}", "pbcore:#{PBCORE_NAMESPACE}").each do |node|
      yield node
    end
  end
end
