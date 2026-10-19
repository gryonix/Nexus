package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.app.secrets.SecretStore

fun eraser(secrets: SecretStore = InMemorySecretStore()) = DeploymentEraser(secrets)
