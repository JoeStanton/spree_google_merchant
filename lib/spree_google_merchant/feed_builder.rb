require 'net/ftp'

module SpreeGoogleMerchant
  class FeedBuilder
    include Spree::Core::Engine.routes.url_helpers

    attr_reader :store, :domain, :title

    def self.generate_and_transfer
      self.builders.each do |builder|
        builder.generate_and_transfer_store
      end
    end

    def self.generate
      self.builders.each do |builder|
        builder.generate_store
      end
    end

    def self.transfer
      self.builders.each do |builder|
        builder.transfer_xml
      end
    end

    def self.builders
      if defined?(Spree::Store)
        Spree::Store.all.map{ |store| self.new(:store => store) }
      else
        [self.new]
      end
    end

    def initialize(opts = {})
      raise "Please pass a public address as the second argument, or configure :public_path in Spree::GoogleMerchant::Config" unless
          opts[:store].present? or (opts[:path].present? or Spree::GoogleMerchant::Config[:public_domain])

      @store = opts[:store] if opts[:store].present?
      @title = @store ? @store.name : Spree::GoogleMerchant::Config[:store_name]

      @domain = @store ? @store.domains.match(/[\w\.]+/).to_s : opts[:path]
      @domain ||= Spree::GoogleMerchant::Config[:public_domain]
    end

    def ar_scope
      if @store
        Spree::Product.by_store(@store).google_merchant_scope.scoped
      else
        Spree::Product.google_merchant_scope.scoped
      end
    end

    def generate_store
      delete_xml_if_exists

      File.open(path, 'w') do |file|
        generate_xml file
      end

    end

    def generate_and_transfer_store
      delete_xml_if_exists

      File.open(path, 'w') do |file|
        generate_xml file
      end

      transfer_xml
      cleanup_xml
    end

    def path
      "#{::Rails.root}/tmp/#{filename}"
    end

    def filename
      "google_merchant_v#{@store.try(:code)}.xml"
    end

    def delete_xml_if_exists
      File.delete(path) if File.exists?(path)
    end

    def validate_record(product)
      #return false, "Images Invalid" if product.images.length == 0 || product.imagesize == 0
      return false, "Title Invalid" if product.google_merchant_title.blank?
      return false, "Category Invalid" if product.google_merchant_product_category.blank?
      return false, "No Availablity" if product.google_merchant_availability.blank?
      return false, "Price Invalid" if product.google_merchant_price.blank?
      return false, "Description Invalid" if product.google_merchant_description.blank?
      return false, "Brand Invalid" if product.google_merchant_brand.blank?
      #return false, "GTIN Invalid" if product.google_merchant_gtin.blank?
      return false, "SKU Invalid" if product.google_merchant_mpn.blank?
      return false, "Shipping Weight Invalid" if product.google_merchant_shipping_weight.blank?
      #return false, "UPC Invalid" unless validate_upc(product.master.gtin)
      unless product.google_merchant_sale_price.blank?
        return false, "Invalid sale price" if product.google_merchant_sale_price_effective.blank?
      end

      true
    end

    def generate_xml output
      xml = Builder::XmlMarkup.new(:target => output)
      xml.instruct!

      xml.rss(:version => '2.0', :"xmlns:g" => "http://base.google.com/ns/1.0") do
        xml.channel do
          build_meta(xml)

          ar_scope.find_each(:batch_size => 300) do |product|
            valid, msg = validate_record(product)
            if valid
              build_product(xml, product)
            else
              puts "#{product.name} Failed: #{msg}"
            end
          end
        end
      end
    end

    def transfer_xml
      raise "Please configure your Google Merchant :ftp_username and :ftp_password by configuring Spree::GoogleMerchant::Config" unless
          Spree::GoogleMerchant::Config[:ftp_username] and Spree::GoogleMerchant::Config[:ftp_password]

      ftp = Net::FTP.new('uploads.google.com')
      ftp.passive = true
      ftp.login(Spree::GoogleMerchant::Config[:ftp_username], Spree::GoogleMerchant::Config[:ftp_password])
      ftp.put(path, filename)
      ftp.quit
    end

    def cleanup_xml
      File.delete(path)
    end

    def build_product(xml, product)
      xml.item do
        xml.tag!('link', product_url(product.slug, :host => domain))
        build_images(xml, product)

        GOOGLE_MERCHANT_ATTR_MAP.each do |k, v|
          value = product.send("google_merchant_#{v}")
          xml.tag!(k, value.to_s) if value.present?
        end
        build_adwords_labels(xml, product)
        build_custom_labels(xml, product)
      end
    end

    def build_images(xml, product)
      main_image, *more_images = product.master.images

      return unless main_image
      xml.tag!('g:image_link', image_url(main_image).sub(/\?.*$/, '').sub(/^\/\//, 'http://'))

      more_images.each do |image|
        xml.tag!('g:additional_image_link', image_url(image).sub(/\?.*$/, '').sub(/^\/\//, 'http://'))
      end
    end

    def image_url image
      base_url = image.attachment.url(:large)
      base_url = "#{domain}/#{base_url}" unless Spree::Config[:use_s3]

      base_url
    end

    def validate_upc(upc)
      return false if upc.nil?
      digits = upc.split('')
      len = upc.length
      return false unless [8,12,13,14].include? len
      check = 0
      digits.reverse.drop(1).reverse.each_with_index do |i,index|
        check += (index.to_i % 2 == len % 2 ? i.to_i * 3 : i.to_i )
      end
      ((10 - check % 10) % 10) == digits.last.to_i
    end

    # <g:adwords_labels>
    def build_adwords_labels(xml, product)

      labels = []

      taxon = product.taxons.first
      unless taxon.nil?
        taxon.self_and_ancestors.each do |taxon|
          labels << taxon.name
        end
      end

      list = [:category,:group,:type,:theme,:keyword,:color,:shape,:brand,:size,:material,:for,:agegroup]
      list.each do |prop|
        if labels.length < 10 then
          value = product.property(prop)
          labels << value if value.present?
        end
      end



      labels.slice(0..9).each do |l|
        xml.tag!('g:adwords_labels', l)
      end
    end

    def build_custom_labels(xml, product)
      xml.tag!('g:custom_label_0', product.google_merchant_availability)
    end

    def build_meta(xml)
      xml.title @title
      xml.link @domain
    end

  end
end
