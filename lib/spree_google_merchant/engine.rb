module SpreeGoogleMerchant
  class Engine < Rails::Engine
    engine_name 'spree_google_merchant'

    config.autoload_paths += %W( #{config.root}/lib )

    initializer "spree.google_merchant.environment", :before => :load_config_initializers do |app|
      Spree::GoogleMerchant::Config = Spree::GoogleMerchantConfiguration.new

      # See http://support.google.com/merchants/bin/answer.py?hl=en&answer=188494#US for all other fields
      SpreeGoogleMerchant::FeedBuilder::GOOGLE_MERCHANT_ATTR_MAP = [
        ['g:id', 'id'],
        ['title', 'title'],
        ['description', 'description'],
        ['g:google_product_category','product_category'],
        ['g:product_type', 'product_type'],
        ['g:condition', 'condition'],
        ['g:availability', 'availability'],
        ['g:price', 'price'],
        ['g:sale_price', 'sale_price'],
        ['g:sale_price_effective_date', 'sale_price_effective_date'],
        ['g:brand', 'brand'],
        ['g:gtin','gtin'],
        ['g:mpn', 'mpn'],
        ['g:gender', 'gender'],
        ['g:age_group', 'age_group'],
        ['g:color', 'color'],
        ['g:size', 'size'],
        ['g:shipping_weight', 'shipping_weight'],
        ['g:adult', 'adult'],
        ['g:adwords_grouping', 'adwords_group']
      ]
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), "../../app/**/*_decorator*.rb")) do |c|
        Rails.application.config.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare &method(:activate).to_proc

  end
end