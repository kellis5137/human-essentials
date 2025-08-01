RSpec.describe "Admin::Organizations", type: :request do
  let(:organization) { create(:organization, email: "email@testthis.com") }

  context "When logged in as a super admin" do
    before do
      sign_in(create(:super_admin, organization: organization))
    end

    describe "GET #new" do
      it "returns http success" do
        get new_admin_organization_path
        expect(response).to be_successful
      end

      context 'when given a valid account request token in the query parameters' do
        let!(:account_request) { create(:account_request) }

        it 'should render new with pre populate input fields from the account_request' do
          ndbn_member = create(:ndbn_member)
          account_request.ndbn_member = ndbn_member
          account_request.save

          get new_admin_organization_url(token: account_request.identity_token)
          expect(response).to render_template(:new)

          # Just checking if the values appear in the template. This assumes
          # that if they are present in the body then they are pre-populating
          # the form. A system test will likely handle this test case.
          #
          # Using CGI.escapeHTML to match account_request attribute which is rendered
          # to be HTML safe. If the organization_name or any attribute has unsafe characters
          # then this test would fail. For example, if the organization_name were
          # "Pouros, O'Kon and Schumm"
          #
          # rubocop:disable Style/ColonMethodCall
          expect(response.body).to match(CGI::escapeHTML(account_request.name))
          expect(response.body).to match(CGI::escapeHTML(account_request.email))
          expect(response.body).to match(CGI::escapeHTML(account_request.organization_name))
          expect(response.body).to match(CGI::escapeHTML(account_request.organization_website))
          expect(response.body).to match(CGI::escapeHTML("#{ndbn_member.ndbn_member_id} - #{ndbn_member.account_name}"))
          # rubocop:enable Style/ColonMethodCall
        end
      end

      context 'when given a token that matches a account request that has already been processed' do
        let!(:account_request) { FactoryBot.create(:account_request) }

        before do
          FactoryBot.create(:organization, account_request_id: account_request.id)
        end

        it 'should render new with a flash error message' do
          get new_admin_organization_url(token: account_request.identity_token)
          expect(response).to render_template(:new)

          expect(response.body).to include("The account request had already been processed and cannot be used again")
        end
      end
    end

    describe "POST #create" do
      let(:valid_organization_params) { attributes_for(:organization, user: { name: 'admin', email: 'admin@example.com'}).except(:logo) }

      context "with valid params" do
        it "creates an organization and redirects to #index" do
          expect {
            post admin_organizations_path({ organization: valid_organization_params })
          }.to change(Organization, :count).by(1)
            .and change(SnapshotEvent, :count).by(1)
          expect(response).to redirect_to(admin_organizations_path)
        end
      end

      context "with invalid params" do
        let(:invalid_params) { valid_organization_params.merge(name: nil) }

        it "does not create an organization and renders #create with an error message" do
          expect {
            post admin_organizations_path({ organization: invalid_params })
          }.to change(Organization, :count).by(0)

          expect(subject).to render_template("new")
          expect(flash[:error]).to be_present
        end

        it "preserves user attributes" do
          post admin_organizations_path({ organization: invalid_params })

          expect(subject).to render_template("new")
          expect(response.body).to include(invalid_params[:user][:name])
          expect(response.body).to include(invalid_params[:user][:email])
        end
      end
    end

    describe "GET #index" do
      it "returns http success" do
        get admin_organizations_path
        expect(response).to be_successful
        expect(response.body).to include(organization.name)
        expect(response.body).to include(organization.email)
        expect(response.body).to include(organization.created_at.strftime("%Y-%m-%d"))
        expect(response.body).to include(organization.display_last_distribution_date)
      end
    end

    describe "DELETE #destroy" do
      let(:organization) { create(:organization) }

      context "with a valid organization id" do
        it "redirects to #index" do
          delete admin_organization_path({ id: organization.id })
          expect(response).to redirect_to(admin_organizations_path)
        end
      end
    end

    describe "GET #show" do
      let!(:organization) { create(:organization) }

      it "returns http success" do
        get admin_organization_path({ id: organization.id })
        expect(response).to be_successful
      end

      it "displays the correct organization details" do
        intake_storage_location = create(:storage_location, organization:, name: "Intake Center")
        default_storage_location = create(:storage_location, organization:, name: "Default Center")

        organization.update!(intake_location: intake_storage_location.id, default_storage_location: default_storage_location.id)

        get admin_organization_path({ id: organization.id })

        expect(response.body).to include("Intake Center")
        expect(response.body).to include("Default Center")
      end

      context "with an organization user" do
        let!(:user) { create(:user, organization: organization) }

        it "provides links to edit the user" do
          get admin_organization_path({ id: organization.id })

          expect(response.body).to include("Actions")
          expect(response.body).to include('Promote to Admin')
          expect(response.body).to include(promote_to_org_admin_organization_path(user_id: user.id))
          expect(response.body).to include('Remove User')
          expect(response.body).to include(remove_user_organization_path(user_id: user.id))
        end
      end
    end

    describe "DELETE #destroy" do
      it "redirects" do
        delete admin_organization_path({ id: organization.id })
        expect(response).to redirect_to(admin_organizations_path)
      end
    end
  end

  context "When logged in as a non-admin user" do
    before do
      sign_in(create(:user, organization: organization))
    end

    describe "GET #new" do
      it "redirects" do
        get new_admin_organization_path
        expect(response).to be_redirect
      end
    end

    describe "POST #create" do
      it "redirects" do
        post admin_organizations_path({ organization: attributes_for(:organization) })
        expect(response).to be_redirect
      end
    end

    describe "GET #index" do
      it "redirects" do
        get admin_organizations_path
        expect(response).to be_redirect
      end
    end
  end
end
