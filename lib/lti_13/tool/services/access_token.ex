defmodule Lti13.Tool.Services.AccessToken do
  alias Lti13.Jwks

  use Joken.Config

  @enforce_keys [:access_token, :token_type, :expires_in, :scope]
  defstruct [:access_token, :token_type, :expires_in, :scope]

  @type t() :: %__MODULE__{
          access_token: String.t(),
          token_type: String.t(),
          expires_in: integer(),
          scope: String.t()
        }

  @doc """
  Requests an OAuth2 access token. Returns {:ok, %AccessToken{}} on success, {:error, error}
  otherwise.

  As parameters, expects:
  1. The registration from which an access token is being requested
  2. A list of scopes being requested
  3. The host name of this instance of Torus

  ## Examples

      iex> fetch_access_token(registration, scopes, host)
      {:ok,
        %Lti13.Tool.Services.AccessToken{
          "scope" => "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
          "access_token" => "actual_access_token",
          "token_type" => "Bearer",
          "expires_in" => "3600"
        }
      }

      iex> fetch_access_token(bad_tool)
      {:error, "invalid_scope"}
  """
  def fetch_access_token(
        %{auth_token_url: auth_token_url, client_id: client_id, auth_server: auth_audience},
        scopes,
        _host
      ) do
    client_assertion =
      create_client_assertion(%{
        auth_token_url: auth_token_url,
        client_id: client_id,
        auth_aud: auth_audience
      })

    request_token(auth_token_url, client_assertion, scopes)
  end

  def fetch_access_token(lti_resource) do
    Lti13.Tool.Services.AccessToken.fetch_access_token(
      %{
        auth_token_url: lti_resource.registration.auth_token_url,
        client_id: lti_resource.registration.client_id,
        auth_server: lti_resource.registration.auth_server
      },
      [
        "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
        "https://purl.imsglobal.org/spec/lti-ags/scope/score"
      ],
      Application.get_env(:claper, ClaperWeb.Endpoint)[:url][:host]
    )
  end

  defp request_token(url, client_assertion, scopes) do
    body =
      [
        grant_type: "client_credentials",
        client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        client_assertion: client_assertion,
        scope: Enum.join(scopes, " ")
      ]
      |> URI.encode_query()

    headers = %{"Content-Type" => "application/x-www-form-urlencoded"}

    with {:ok, %Req.Response{status: 200, body: body}} <-
           Req.post(url, body: body, headers: headers),
         {:ok, parsed_body} <- Jason.decode(body) do
      {:ok,
       %__MODULE__{
         access_token: Map.get(parsed_body, "access_token"),
         token_type: Map.get(parsed_body, "token_type"),
         expires_in: Map.get(parsed_body, "expires_in"),
         scope: Map.get(parsed_body, "scope")
       }}
    else
      {:error, %Jason.DecodeError{}} ->
        {:error, "Invalid JSON response"}

      e ->
        {:error, "Error fetching access token: #{inspect(e)}"}
    end
  end

  defp create_client_assertion(%{
         auth_token_url: auth_token_url,
         client_id: client_id,
         auth_aud: auth_audience
       }) do
    # Get the active private key
    active_jwk = Jwks.get_active_jwk()

    # Sign and return the JWT, include the kid of the key we are using
    # in the header.
    custom_header = %{"kid" => active_jwk.kid}
    signer = Joken.Signer.create("RS256", %{"pem" => active_jwk.pem}, custom_header)

    # define our custom claims
    custom_claims = %{
      "iss" => client_id,
      "aud" => audience(auth_token_url, auth_audience),
      "sub" => client_id
    }

    {:ok, token, _} = generate_and_sign(custom_claims, signer)

    token
  end

  defp audience(auth_token_url, nil), do: auth_token_url
  defp audience(auth_token_url, ""), do: auth_token_url
  defp audience(_auth_token_url, auth_audience), do: auth_audience
end
