# encoding:utf-8
module SpreePaypalExpress
  module ParameterMethods
    
    extend ActiveSupport::Concern
    
    private

    def asset_url(_path)
      URI::HTTP.build(:path => ActionController::Base.helpers.asset_path(_path), :host => Spree::Config[:site_url].strip).to_s
    end

    def record_log(payment, response)
      payment.log_entries.create(:details => response.to_yaml)
    end
    
    def fixed_opts
      if Spree::PaypalExpress::Config[:paypal_express_local_confirm].nil?
        user_action = "continue"
      else
        user_action = Spree::PaypalExpress::Config[:paypal_express_local_confirm] == "t" ? "continue" : "commit"
      end

      #asset_url doesn't like Spree::Config[:logo] being an absolute url
      #if statement didn't work within hash
      if URI.parse(Spree::Config[:logo]).absolute?
          chosen_image = Spree::Config[:logo]
      else
          chosen_image = asset_url(Spree::Config[:logo])
      end


      { :description             => "#{I18n.t(:paypal_cart_from)} #{Spree::Config[:site_name]}", # site details...
        #:page_style             => "foobar", # merchant account can set named config
        :background_color        => "ffffff",  # must be hex only, six chars
        :header_background_color => "ffffff",
        :header_border_color     => "ffffff",
        :header_image            => chosen_image,
        :allow_note              => Spree::Config[:shipping_instructions],
        :locale                  => user_locale,
        :req_confirm_shipping    => false,   # for security, might make an option later
        :user_action             => user_action

        # WARNING -- don't use :ship_discount, :insurance_offered, :insurance since
        # they've not been tested and may trigger some paypal bugs, eg not showing order
        # see http://www.pdncommunity.com/t5/PayPal-Developer-Blog/Displaying-Order-Details-in-Express-Checkout/bc-p/92902#C851
      }
    end

    def user_locale
      I18n.locale.to_s
    end

    # hook to override paypal site options
    def paypal_site_opts
      {:currency => payment_method.preferred_currency, :allow_guest_checkout => payment_method.preferred_allow_guest_checkout }
    end

    def order_opts(order, payment, stage, return_url, cancel_url)
#      items = order.line_items.map do |item|
#        price = (item.price * 100).to_i # convert for gateway
#        { :name        => item.variant.product.name.gsub(/<\/?[^>]*>/, ""),
#          :description => (item.variant.product.description[0..120].gsub(/<\/?[^>]*>/, "") if item.variant.product.description),
#          :number      => item.variant.sku,
#          :quantity    => item.quantity,
#          :amount      => price,
#          :weight      => item.variant.weight,
#          :height      => item.variant.height,
#          :width       => item.variant.width,
#          :depth       => item.variant.weight }
#        end

      credits = order.adjustments.eligible.map do |credit|
        if credit.amount < 0.00
          { :name        => credit.label,
            :description => credit.label,
            :sku         => credit.id,
            :quantity    => 1,
            :amount      => (credit.amount*100).to_i }
        end
      end

      credits_total = 0
      credits.compact!
      if credits.present?
#        items.concat credits
        credits_total = credits.map {|i| i[:amount] * i[:quantity] }.sum
      end

#      if payment_method.preferred_cart_checkout and (order.shipping_method.blank? or order.ship_total == 0)
#        shipping_cost  = shipping_options[:shipping_options].first[:amount]
#        order_total    = (order.total * 100 + (shipping_cost)).to_i
#        shipping_total = (shipping_cost).to_i
#      else
#        order_total    = (order.total * 100).to_i
#        shipping_total = (order.ship_total * 100).to_i
#      end
      order_total    = (order.total * 100).to_i
      shipping_total = (order.ship_total * 100).to_i

      opts = { :return_url        => return_url,
               :cancel_return_url => cancel_url,
               :order_id          => payment.id,
               :custom            => order.number,
#               :items             => items,
               :subtotal          => ((order.item_total * 100) + credits_total).to_i,
               :tax               => (order.tax_total*100).to_i,
               :shipping          => shipping_total,
               :money             => order_total,
               :max_amount        => (order.total * 300).to_i}

      if stage == "checkout"
        raise # not used by us
#        opts[:handling] = 0
#
#        opts[:callback_url] = spree.root_url + "paypal_express_callbacks/#{order.number}"
#        opts[:callback_timeout] = 3
      elsif stage == "payment"
        #hack to add float rounding difference in as handling fee - prevents PayPal from rejecting orders
        #because the integer totals are different from the float based total. This is temporary and will be
        #removed once Spree's currency values are persisted as integers (normally only 1c)
        if payment_method.preferred_cart_checkout
          opts[:handling] = 0
        else
          opts[:handling] = (order.total*100).to_i - opts.slice(:subtotal, :tax, :shipping).values.sum
        end
      end

      opts
    end

#    def shipping_options
#      # Uses users address if exists (from spree_address_book or custom implementation), if not uses first shipping method.
#      if spree_current_user.present? && spree_current_user.respond_to?(:addresses) && spree_current_user.addresses.present?
#        estimate_shipping_for_user
#        shipping_default = @rate_hash_user.map.with_index do |shipping_method, idx|
#          if @order.shipping_method_id
#            default = (@order.shipping_method_id == shipping_method.id)
#          else
#            default = (idx == 0)
#          end
#          {
#            :default => default,
#            :name    => shipping_method.name,
#            :amount  => (shipping_method.cost*100).to_i
#          }
#        end
#      else
#        shipping_method = @order.shipping_method_id ? ShippingMethod.find(@order.shipping_method_id) : ShippingMethod.all.first
#        shipping_default = [{ :default => true,
#                              :name => shipping_method.name,
#                              :amount => ((shipping_method.calculator.compute(@order).to_f) * 100).to_i }]
#      end
#
#      {
#        :callback_url      => spree.root_url + "paypal_shipping_update",
#        :callback_timeout  => 6,
#        :callback_version  => '61.0',
#        :shipping_options  => shipping_default
#      }
#    end

    def address_options(order)
      if payment_method.preferred_no_shipping
        { :no_shipping => true }
      else
        {
          :no_shipping => false,
          :address_override => true,
          :address => {
            :name       => "#{order.ship_address.firstname} #{order.ship_address.lastname}",
            :address1   => order.ship_address.address1,
            :address2   => order.ship_address.address2,
            :city       => order.ship_address.city,
            :state      => order.ship_address.state.nil? ? order.ship_address.state_name.to_s : order.ship_address.state.abbr,
            :country    => order.ship_address.country.iso,
            :zip        => order.ship_address.zipcode,
            :phone      => order.ship_address.phone
          }
        }
      end
    end

    def all_opts(order, payment, stage, return_url, cancel_url)
      opts = fixed_opts.merge(order_opts(order, payment, stage, return_url, cancel_url)).merge(paypal_site_opts)

      if stage == "payment"
        opts.merge! flat_rate_shipping_and_handling_options(order, stage)
      end

      opts[:email] = order.user.email
      if order.bill_address.present?
        opts[:address_override] = 1
        opts[:address] = {
          :name => order.bill_address.full_name,
          :zip => order.bill_address.zipcode,
          :address1 => order.bill_address.address1,
          :address2 => order.bill_address.address2,
          :city => order.bill_address.city,
          :phone => order.bill_address.phone,
          :state => order.bill_address.state_text,
          :country => order.bill_address.country.iso
        }
      end
      opts
    end

    # hook to allow applications to load in their own shipping and handling costs
    def flat_rate_shipping_and_handling_options(order, stage)
      # max_fallback = 0.0
      # shipping_options = ShippingMethod.all.map do |shipping_method|
      #           { :name       => "#{shipping_method.name}",
      #             :amount      => (shipping_method.rate),
      #             :default     => shipping_method.is_default }
      #         end


      # default_shipping_method = ShippingMethod.find(:first, :conditions => {:is_default => true})

      # opts = { :shipping_options  => shipping_options,
      #        }

      # #opts[:shipping] = (default_shipping_method.nil? ? 0 : default_shipping_method.fallback_amount) if stage == "checkout"

      # opts
      {}
    end
    
#    def add_shipping_charge
#      # Replace with these changes once Active_Merchant pushes pending pull request
#      # shipment_name = @ppx_details.shipping['amount'].chomp(" Shipping")
#      # shipment_cost = @ppx_details.shipping['name'].to_f
#
#      shipment_name = @ppx_details.params['UserSelectedOptions']['ShippingOptionName'].chomp(" Shipping")
#      shipment_cost = @ppx_details.params['UserSelectedOptions']['ShippingOptionAmount'].to_f
#      if @order.shipping_method_id.blank? && @order.rate_hash.present?
#        selected_shipping = @order.rate_hash.detect { |v| v['name'] == shipment_name && v['cost'] == shipment_cost }
#        @order.shipping_method_id = selected_shipping.id
#      end
#      @order.shipments.each { |s| s.destroy unless s.shipping_method.available_to_order?(@order) }
#      @order.create_shipment!
#      @order.update!
#    end

#    def estimate_shipping_for_user
#      zipcode = spree_current_user.addresses.first.zipcode
#      country = spree_current_user.addresses.first.country.iso
#      shipping_methods = Spree::ShippingMethod.all
#      #TODO remove hard coded shipping
#      #Make a deep copy of the order object then stub out the parts required to get a shipping quote
#      @shipping_order = Marshal::load(Marshal.dump(@order)) #Make a deep copy of the order object
#      @shipping_order.ship_address = Spree::Address.new(:country => Spree::Country.find_by_iso(country), :zipcode => zipcode)
#      shipment = Spree::Shipment.new(:address => @shipping_order.ship_address)
#      @shipping_order.ship_address.shipments<<shipment
#      @shipping_order.shipments<<shipment
#      @rate_hash_user = @shipping_order.rate_hash
#      #TODO
#    end
  end
end
