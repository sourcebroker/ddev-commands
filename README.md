## Getting started

### ci-pipline-status

Before `ddev ci-pipeline-status` can work you need to:
1. Create a folder in your home directory `~/.config/ddev-ci/`.
2. Create a file `config.yaml` in `~/.config/ddev-ci/`.
3. In file `config.yaml` add the following content:
    ```yaml
    hosts:
      gitlab.com:
        api_host: gitlab.com
        token: ....
      gitlab.example.com:
        api_host: gitlab.example.com
        token: ....

    ```

To get token you need to:
1. Open `https://<gitlab-server>/-/user_settings/personal_access_tokens`
2. Click button "Add new token"
3. Choose a name for the token and select scopes: `api` and `read_repository`.
