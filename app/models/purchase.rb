# == Schema Information
#
# Table name: purchases
#
#  id                                       :bigint           not null, primary key
#  amount_spent_in_cents                    :integer
#  amount_spent_on_adult_incontinence_cents :integer          default(0), not null
#  amount_spent_on_diapers_cents            :integer          default(0), not null
#  amount_spent_on_other_cents              :integer          default(0), not null
#  amount_spent_on_period_supplies_cents    :integer          default(0), not null
#  comment                                  :text
#  issued_at                                :datetime
#  purchased_from                           :string
#  created_at                               :datetime         not null
#  updated_at                               :datetime         not null
#  organization_id                          :integer
#  storage_location_id                      :integer
#  vendor_id                                :integer
#

class Purchase < ApplicationRecord
  has_paper_trail
  include MoneyRails::ActionViewExtension

  belongs_to :organization
  belongs_to :storage_location
  belongs_to :vendor

  include Itemizable
  include Filterable
  include IssuedAt
  include Exportable

  monetize :amount_spent_in_cents, as: :amount_spent
  monetize :amount_spent_on_diapers_cents
  monetize :amount_spent_on_adult_incontinence_cents
  monetize :amount_spent_on_period_supplies_cents
  monetize :amount_spent_on_other_cents

  before_save :strip_symbols_from_money

  scope :at_storage_location, ->(storage_location_id) {
                                where(storage_location_id: storage_location_id)
                              }
  scope :from_vendor, ->(vendor_id) {
    where(vendor_id: vendor_id)
  }
  scope :purchased_from, ->(purchased_from) { where(purchased_from: purchased_from) }
  scope :during, ->(range) { where(purchases: { issued_at: range }) }
  scope :recent, ->(count = 3) { order(issued_at: :desc).limit(count) }

  scope :active, -> { joins(:line_items).joins(:items).where(items: { active: true }) }

  scope :by_category, ->(item_category) {
    joins(line_items: {item: :item_category}).where("item_categories.name ILIKE ?", item_category)
  }

  before_create :combine_duplicates

  validates :amount_spent_in_cents, numericality: { greater_than: 0 }
  validate :total_equal_to_all_categories

  validates :amount_spent_on_diapers_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :amount_spent_on_adult_incontinence_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :amount_spent_on_period_supplies_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :amount_spent_on_other_cents, numericality: { greater_than_or_equal_to: 0 }

  SummaryByDates = Data.define(
    :amount_spent,
    :recent_purchases,
    :period_supplies,
    :diapers,
    :adult_incontinence,
    :other,
    :total_items
  )

  def storage_view
    storage_location.nil? ? "N/A" : storage_location.name
  end

  def purchased_from_view
    vendor.nil? ? purchased_from : vendor.business_name
  end

  # @return [Integer]
  def amount_spent_in_dollars
    amount_spent.dollars.to_f
  end

  def self.organization_summary_by_dates(organization, date_range)
    purchases = where(organization: organization).during(date_range)

    SummaryByDates.new(
      amount_spent: purchases.sum(:amount_spent_in_cents),
      recent_purchases: purchases.recent.includes(:vendor),
      period_supplies: purchases.sum(:amount_spent_on_period_supplies_cents),
      diapers: purchases.sum(:amount_spent_on_diapers_cents),
      adult_incontinence: purchases.sum(:amount_spent_on_adult_incontinence_cents),
      other: purchases.sum(:amount_spent_on_other_cents),
      total_items: purchases.joins(:line_items).sum(:quantity)
    )
  end

  private

  def combine_duplicates
    Rails.logger.info "[!] Purchase.combine_duplicates: Combining!"
    line_items.combine!
  end

  def strip_symbols_from_money
    %w[amount_spent amount_spent_on_diapers amount_spent_on_adult_incontinence amount_spent_on_period_supplies amount_spent_on_other].each do |field|
      if self[field].is_a?(String)
        self[field] = self[field].tr("$", "").tr(",", "").to_i
      end
    end
  end

  def total_equal_to_all_categories
    return unless amount_spent&.nonzero?
    return if !amount_spent_on_diapers&.nonzero? &&
      !amount_spent_on_adult_incontinence&.nonzero? &&
      !amount_spent_on_period_supplies&.nonzero? &&
      !amount_spent_on_other.nonzero?

    category_total = amount_spent_on_diapers + amount_spent_on_adult_incontinence + amount_spent_on_period_supplies + amount_spent_on_other
    if category_total != amount_spent
      cat_total = humanized_money_with_symbol(category_total)
      total = humanized_money_with_symbol(amount_spent)
      errors.add(:amount_spent,
        "does not equal all categories - categories add to #{cat_total} but given total is #{total}")
    end
  end
end
