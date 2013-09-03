# encoding:utf-8
module SpreePaypalExpress
  module ResultRendering
    extend ActiveSupport::Concern
    
    private

    def render_success
      flash[:notice] = I18n.t(:order_processed_successfully)
      flash[:commerce_tracking] = "true"
      redirect_to completion_route
    end
    
    def render_error(error_thing)
      gateway_error error_thing
      redirect_to edit_order_checkout_url(@order, :state => "payment")
    end
    
    def render_cancel(error_thing)
      flash[:error] = error_thing
      redirect_to edit_order_checkout_url(@order, :state => "payment")
    end
    
  end
end
