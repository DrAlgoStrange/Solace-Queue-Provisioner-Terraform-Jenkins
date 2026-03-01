// =============================================================================
// Jenkinsfile — Solace Queue Provisioner
//
// MessageQueue.yaml format:
//   queues:
//     - name:   "q/MyQueue"          # required
//       dmq:    "dmq/MyQueue"        # optional — name of DMQ to associate
//                                    # omit or leave "" for no DMQ
//       topics:                      # optional — omit or [] for no subscriptions
//         - "my/topic/string"
//         - "another/topic/>"
//
// Regular vs DMQ queues are split automatically:
//   - A queue whose name appears as another entry's 'dmq' value → DMQ queue
//   - All other queues → regular queues
//
// DeadMessageQueue.yaml is NO LONGER used — remove it from your repo.
//
// Actions:
//   plan          = show what Terraform would create/change (no changes made)
//   apply         = create / update all queues + subscriptions
//   delete-queues = permanently delete all queues + subscriptions via SEMPv2 API
//
// Jenkins Plugin Requirements:
//   - Pipeline: Declarative
//   - Pipeline Utility Steps  (readYaml, readJSON, writeJSON)
//   - Git
//   - Credentials Binding
//   - Workspace Cleanup
//   - HTTP Request  (for delete-queues)
// =============================================================================

pipeline {

    agent any

    parameters {

        string(
            name:         'GITHUB_REPO_URL',
            defaultValue: '',
            description:  'GitHub repository URL.\nExample: https://github.com/your-org/your-repo.git'
        )

        string(
            name:         'GITHUB_BRANCH',
            defaultValue: 'main',
            description:  'Git branch to checkout (e.g. main, develop, feature/my-branch)'
        )

        string(
            name:         'GITHUB_CREDENTIALS',
            defaultValue: '',
            description:  '[OPTIONAL] Jenkins Credentials ID for private GitHub repos.\nLeave blank for public repositories.'
        )

        choice(
            name:    'TERRAFORM_ACTION',
            choices: ['plan', 'apply', 'delete-queues'],
            description: '''Action to perform:
  plan          = dry-run — show exactly what would be created/changed, no changes made to Solace
  apply         = create / update all queues and topic subscriptions defined in MessageQueue.yaml
  delete-queues = permanently delete all queues (and their subscriptions) listed in
                  MessageQueue.yaml via Solace SEMPv2 API'''
        )
    }

    environment {
        TF_IN_AUTOMATION = "1"
        TF_CLI_ARGS      = "-no-color"
    }

    stages {

        // ── 1. Validate Parameters ────────────────────────────────────────────
        stage('Validate Parameters') {
            steps {
                script {
                    logSection("STAGE 1: Validate Parameters")

                    if (!params.GITHUB_REPO_URL?.trim())
                        errorAndFail("GITHUB_REPO_URL is required but was not provided.")
                    if (!params.GITHUB_BRANCH?.trim())
                        errorAndFail("GITHUB_BRANCH is required but was not provided.")

                    logInfo("GitHub Repo   : ${params.GITHUB_REPO_URL}")
                    logInfo("GitHub Branch : ${params.GITHUB_BRANCH}")
                    logInfo("Credentials   : ${params.GITHUB_CREDENTIALS ?: '(none — public repo)'}")
                    logInfo("Action        : ${params.TERRAFORM_ACTION}")
                    logInfo("Parameters validated successfully.")
                }
            }
        }

        // ── 2. Checkout Repository ────────────────────────────────────────────
        stage('Checkout Repository') {
            steps {
                script {
                    logSection("STAGE 2: Checkout Repository")
                    cleanWs()

                    def remoteCfg = params.GITHUB_CREDENTIALS?.trim()
                        ? [url: params.GITHUB_REPO_URL, credentialsId: params.GITHUB_CREDENTIALS]
                        : [url: params.GITHUB_REPO_URL]

                    try {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: "*/${params.GITHUB_BRANCH}"]],
                            doGenerateSubmoduleConfigurations: false,
                            extensions: [
                                [$class: 'CleanBeforeCheckout'],
                                [$class: 'CloneOption', timeout: 30]
                            ],
                            userRemoteConfigs: [remoteCfg]
                        ])
                        logInfo("Repository checked out successfully.")
                    } catch (Exception e) {
                        logError("Failed to checkout repository: ${e.getMessage()}")
                        logError("Verify the URL is correct and credentials (if private) are configured in Jenkins.")
                        throw e
                    }

                    logInfo("Repository contents:")
                    sh 'find . -maxdepth 3 -not -path "./.git/*" | sort'
                }
            }
        }

        // ── 3. Validate Required Files ────────────────────────────────────────
        stage('Validate Required Files') {
            steps {
                script {
                    logSection("STAGE 3: Validate Required Files")

                    def required = [
                        'PlatformConfig.yaml',
                        'MessageQueue.yaml',
                        'MessageQueueConfig.yaml',
                        'DeadMessageQueueConfig.yaml',
                        'terraform/main.tf',
                        'terraform/variables.tf',
                        'terraform/outputs.tf',
                    ]

                    def missing = []
                    required.each { f ->
                        if (fileExists(f)) {
                            logInfo("Found : ${f}")
                        } else {
                            missing.add(f)
                            logError("Missing required file: ${f}")
                        }
                    }

                    if (missing)
                        errorAndFail("Required files are missing: ${missing.join(', ')}")

                    logInfo("All required files present.")
                }
            }
        }

        // ── 4. Verify Terraform (skipped for delete-queues) ───────────────────
        stage('Verify Terraform') {
            when {
                expression { params.TERRAFORM_ACTION != 'delete-queues' }
            }
            steps {
                script {
                    logSection("STAGE 4: Verify Terraform")
                    try {
                        shLogged('terraform version', 'Terraform version check')
                    } catch (Exception e) {
                        errorAndFail("Terraform not found on PATH. Install Terraform >= 1.3.0 on the Jenkins agent.")
                    }
                }
            }
        }

        // ── 5. Parse YAML Config ──────────────────────────────────────────────
        stage('Parse YAML Config') {
            steps {
                script {
                    logSection("STAGE 5: Parse YAML Configuration Files (Groovy)")

                    // ── 5a. PlatformConfig.yaml ───────────────────────────────
                    logInfo("Reading PlatformConfig.yaml ...")
                    def platformData = safeReadYaml('PlatformConfig.yaml')
                    def solaceCfg    = platformData?.solace

                    def sempUrl      = solaceCfg?.semp_url?.trim()
                    def messageVpn   = solaceCfg?.message_vpn?.trim()
                    def solaceCredId = solaceCfg?.solace_credentials_id?.trim()

                    if (!sempUrl)      errorAndFail("'solace.semp_url' is blank in PlatformConfig.yaml")
                    if (!messageVpn)   errorAndFail("'solace.message_vpn' is blank in PlatformConfig.yaml")
                    if (!solaceCredId) errorAndFail("'solace.solace_credentials_id' is blank in PlatformConfig.yaml")

                    logInfo("SEMP URL       : ${sempUrl}")
                    logInfo("Message VPN    : ${messageVpn}")
                    logInfo("Solace Cred ID : ${solaceCredId}")

                    env.SOLACE_SEMP_URL = sempUrl
                    env.MESSAGE_VPN     = messageVpn
                    env.SOLACE_CRED_ID  = solaceCredId

                    // ── 5b. MessageQueue.yaml ─────────────────────────────────
                    logInfo("Reading MessageQueue.yaml ...")
                    def allEntries = parseQueueEntries(safeReadYaml('MessageQueue.yaml'), 'MessageQueue.yaml')

                    // Split regular vs DMQ
                    def dmqNamesSet   = allEntries.collect { it.dmq }.findAll { it }.toSet()
                    def regularQueues = allEntries.findAll { !dmqNamesSet.contains(it.name) }
                    def dmqQueues     = allEntries.findAll {  dmqNamesSet.contains(it.name) }

                    logInfo("Regular queues (${regularQueues.size()}):")
                    regularQueues.each { q ->
                        logInfo("  ${q.name}  |  DMQ: ${q.dmq ?: '(none)'}  |  Topics (${q.topics.size()}): ${q.topics ?: '(none)'}")
                    }
                    logInfo("Dead Message Queues (${dmqQueues.size()}):")
                    dmqQueues.each { q ->
                        logInfo("  ${q.name}  |  Topics (${q.topics.size()}): ${q.topics ?: '(none)'}")
                    }

                    // Validate every declared dmq name has a matching queue entry
                    def allNames = allEntries.collect { it.name }.toSet()
                    regularQueues.each { q ->
                        if (q.dmq && !allNames.contains(q.dmq))
                            errorAndFail("Queue '${q.name}' declares dmq '${q.dmq}' but no queue entry with that name exists in MessageQueue.yaml")
                    }

                    // ── 5c. Config blocks ─────────────────────────────────────
                    logInfo("Reading MessageQueueConfig.yaml ...")
                    def mqConfig = normalizeQueueConfig(safeReadYaml('MessageQueueConfig.yaml'), 'MessageQueueConfig.yaml')
                    logInfo("MessageQueueConfig parsed and validated OK.")

                    logInfo("Reading DeadMessageQueueConfig.yaml ...")
                    def dmqConfig = normalizeQueueConfig(safeReadYaml('DeadMessageQueueConfig.yaml'), 'DeadMessageQueueConfig.yaml')
                    logInfo("DeadMessageQueueConfig parsed and validated OK.")

                    // ── 5d. Write tfvars (plan + apply only) ──────────────────
                    if (params.TERRAFORM_ACTION != 'delete-queues') {
                        withCredentials([
                            usernamePassword(
                                credentialsId: env.SOLACE_CRED_ID,
                                usernameVariable: 'SOLACE_USERNAME',
                                passwordVariable: 'SOLACE_PASSWORD'
                            )
                        ]) {
                            def tfvars = [
                                semp_url       : env.SOLACE_SEMP_URL,
                                admin_username : env.SOLACE_USERNAME,
                                admin_password : env.SOLACE_PASSWORD,
                                message_vpn    : env.MESSAGE_VPN,
                                message_queues : allEntries,
                                mq_config      : mqConfig,
                                dmq_config     : dmqConfig,
                            ]
                            writeJSON file: 'terraform/terraform.tfvars.json', json: tfvars, pretty: 2
                            logInfo("terraform/terraform.tfvars.json written successfully.")
                        }

                        // Sanitised preview
                        def preview = readJSON file: 'terraform/terraform.tfvars.json'
                        preview.admin_username = '***REDACTED***'
                        preview.admin_password = '***REDACTED***'
                        logInfo("tfvars preview (credentials redacted):\n${groovy.json.JsonOutput.prettyPrint(groovy.json.JsonOutput.toJson(preview))}")
                    } else {
                        logInfo("Action is delete-queues — skipping tfvars generation.")
                    }

                    env.MQ_COUNT         = "${regularQueues.size()}"
                    env.DMQ_COUNT        = "${dmqQueues.size()}"
                    env.TOPIC_COUNT      = "${allEntries.sum { it.topics.size() } ?: 0}"
                    env.ALL_ENTRIES_JSON = groovy.json.JsonOutput.toJson(allEntries)
                }
            }
        }

        // ── 6. Terraform Init ─────────────────────────────────────────────────
        stage('Terraform Init') {
            when {
                expression { params.TERRAFORM_ACTION != 'delete-queues' }
            }
            steps {
                script { logSection("STAGE 6: Terraform Init") }
                dir('terraform') {
                    script {
                        try {
                            shLogged('terraform init -input=false', 'Terraform init')
                        } catch (Exception e) {
                            errorAndFail("Terraform init failed. Check network access to registry.terraform.io. Error: ${e.getMessage()}")
                        }
                    }
                }
            }
        }

        // ── 7. Terraform Plan ─────────────────────────────────────────────────
        stage('Terraform Plan') {
            when {
                expression { params.TERRAFORM_ACTION in ['plan', 'apply'] }
            }
            steps {
                script { logSection("STAGE 7: Terraform Plan") }
                dir('terraform') {
                    script {
                        try {
                            shLogged(
                                'terraform plan -var-file=terraform.tfvars.json -out=tfplan',
                                'Terraform plan'
                            )
                        } catch (Exception e) {
                            errorAndFail("Terraform plan failed. Verify SEMP URL is reachable and credentials are correct. Error: ${e.getMessage()}")
                        }
                    }
                }
            }
        }

        // ── 8. Terraform Apply ────────────────────────────────────────────────
        stage('Terraform Apply') {
            when {
                expression { params.TERRAFORM_ACTION == 'apply' }
            }
            steps {
                script { logSection("STAGE 8: Terraform Apply") }
                dir('terraform') {
                    script {
                        try {
                            shLogged(
                                'terraform apply -no-color -auto-approve tfplan',
                                'Terraform apply'
                            )
                        } catch (Exception e) {
                            errorAndFail("Terraform apply failed. Review the plan output above. Error: ${e.getMessage()}")
                        }
                    }
                }
            }
        }

        // ── 9. Collect Terraform Outputs ──────────────────────────────────────
        stage('Collect Outputs') {
            when {
                expression { params.TERRAFORM_ACTION == 'apply' }
            }
            steps {
                script { logSection("STAGE 9: Collect Terraform Outputs") }
                dir('terraform') {
                    script {
                        try {
                            def raw = sh(script: 'terraform output -json', returnStdout: true).trim()
                            env.TF_OUTPUTS_JSON = raw
                            logInfo("Terraform outputs:\n${groovy.json.JsonOutput.prettyPrint(raw)}")
                        } catch (Exception e) {
                            logWarn("Could not retrieve Terraform outputs: ${e.getMessage()}")
                        }
                    }
                }
            }
        }

        // ── 10. Delete Queues + Subscriptions via SEMPv2 ─────────────────────
        stage('Delete Queues (SEMPv2)') {
            when {
                expression { params.TERRAFORM_ACTION == 'delete-queues' }
            }
            steps {
                script {
                    logSection("STAGE 10: Delete Queues via Solace SEMPv2 REST API")
                    logWarn("This will PERMANENTLY DELETE all queues and their subscriptions.")
                    logWarn("Target VPN: ${env.MESSAGE_VPN}")

                    withCredentials([
                        usernamePassword(
                            credentialsId: env.SOLACE_CRED_ID,
                            usernameVariable: 'SOLACE_USERNAME',
                            passwordVariable: 'SOLACE_PASSWORD'
                        )
                    ]) {
                        def allEntries = readJSON text: env.ALL_ENTRIES_JSON
                        def sempBase   = env.SOLACE_SEMP_URL.replaceAll('/+$', '')
                        def vpnEnc     = java.net.URLEncoder.encode(env.MESSAGE_VPN, 'UTF-8')

                        int deleted = 0; int skipped = 0; int failed = 0
                        def deletedQueues = []; def skippedQueues = []; def failedQueues = []

                        logInfo("Total queues to process: ${allEntries.size()}")

                        allEntries.each { entry ->
                            def queueName = entry.name
                            def topics    = entry.topics ?: []

                            logInfo("─── ${queueName}  (${topics.size()} subscription(s))")

                            // Step 1 — delete subscriptions first
                            topics.each { topic ->
                                try {
                                    def encQ   = encodeSegments(queueName)
                                    def encT   = encodeSegments(topic)
                                    def subUrl = "${sempBase}/SEMP/v2/config/msgVpns/${vpnEnc}/queues/${encQ}/subscriptions/${encT}"
                                    logInfo("  DEL subscription: ${topic}")
                                    def resp = httpRequest(
                                        url                   : subUrl,
                                        httpMode              : 'DELETE',
                                        authentication        : env.SOLACE_CRED_ID,
                                        validResponseCodes    : '200:299,400:404',
                                        timeout               : 30,
                                        consoleLogResponseBody: false
                                    )
                                    if (resp.status == 200) {
                                        logInfo("  ✔ Subscription deleted: ${topic}")
                                    } else {
                                        logWarn("  - Subscription not found (skipped): ${topic}")
                                    }
                                } catch (Exception e) {
                                    logWarn("  ! Could not delete subscription '${topic}': ${e.getMessage()}")
                                }
                            }

                            // Step 2 — delete the queue
                            try {
                                def encQ     = encodeSegments(queueName)
                                def queueUrl = "${sempBase}/SEMP/v2/config/msgVpns/${vpnEnc}/queues/${encQ}"
                                logInfo("  DEL queue: ${queueName}")
                                def resp = httpRequest(
                                    url                   : queueUrl,
                                    httpMode              : 'DELETE',
                                    authentication        : env.SOLACE_CRED_ID,
                                    validResponseCodes    : '200:299,400:404',
                                    timeout               : 30,
                                    consoleLogResponseBody: false
                                )
                                if (resp.status == 200) {
                                    logInfo("  ✔ Queue deleted: ${queueName}")
                                    deletedQueues << queueName; deleted++
                                } else if (resp.status in [400, 404]) {
                                    logWarn("  - Queue not found (skipped): ${queueName}")
                                    skippedQueues << queueName; skipped++
                                } else {
                                    logError("  ✘ Unexpected HTTP ${resp.status} for: ${queueName}")
                                    failedQueues << "${queueName} (HTTP ${resp.status})"; failed++
                                }
                            } catch (Exception e) {
                                logError("  ✘ Exception deleting '${queueName}': ${e.getMessage()}")
                                failedQueues << "${queueName} (exception: ${e.getMessage()})"; failed++
                            }
                        }

                        logSection("DELETE OPERATION SUMMARY")
                        logInfo("Total processed      : ${allEntries.size()}")
                        logInfo("Successfully deleted  : ${deleted}")
                        logInfo("Skipped (not found)  : ${skipped}")
                        logInfo("Failed               : ${failed}")
                        if (deletedQueues) { logInfo("Deleted:");  deletedQueues.each { logInfo("  ✔  ${it}") } }
                        if (skippedQueues) { logWarn("Skipped:");  skippedQueues.each { logWarn("  -  ${it}") } }
                        if (failedQueues)  { logError("Failed:");  failedQueues.each  { logError("  ✘  ${it}") } }

                        env.DELETE_DELETED = "${deleted}"
                        env.DELETE_SKIPPED = "${skipped}"
                        env.DELETE_FAILED  = "${failed}"

                        if (failed > 0)
                            errorAndFail("${failed} queue(s) could not be deleted. See [FAILED] entries above.")
                    }
                }
            }
        }

    } // end stages

    post {
        always   { script { printSummary() } }
        success  { script { logSection("PIPELINE COMPLETED SUCCESSFULLY") } }
        failure  { script { logSection("PIPELINE FAILED — Review the log above for details") } }
        cleanup  {
            script {
                try {
                    sh 'rm -f terraform/terraform.tfvars.json terraform/tfplan'
                    logInfo("Cleaned up sensitive files from workspace.")
                } catch (_) { /* best-effort */ }
            }
        }
    }

} // end pipeline


// =============================================================================
// GROOVY HELPERS — YAML PARSING
// =============================================================================

def safeReadYaml(String filePath) {
    if (!fileExists(filePath))
        errorAndFail("File not found: ${filePath}")
    try {
        def data = readYaml file: filePath
        if (data == null) errorAndFail("YAML file is empty: ${filePath}")
        return data
    } catch (Exception e) {
        errorAndFail("Failed to parse YAML '${filePath}': ${e.getMessage()}")
    }
}

/**
 * Parse all queue entries from MessageQueue.yaml.
 * Returns List of Maps: [ [name:"...", dmq:"...", topics:[...]], ... ]
 *   dmq    → "" if omitted
 *   topics → [] if omitted
 */
def parseQueueEntries(Map data, String filePath) {
    def rawQueues = data?.queues
    if (rawQueues == null) {
        logWarn("No 'queues' key found in ${filePath}.")
        return []
    }
    if (!(rawQueues instanceof List))
        errorAndFail("'queues' in ${filePath} must be a YAML list.")

    def result = []
    rawQueues.eachWithIndex { entry, idx ->
        if (entry == null)
            errorAndFail("Entry at index ${idx} in ${filePath} is null.")
        if (!(entry instanceof Map))
            errorAndFail("Queue at index ${idx} in ${filePath} must be a map with a 'name' field. Got: '${entry}'")

        String queueName = entry?.name?.toString()?.trim()
        if (!queueName)
            errorAndFail("Queue at index ${idx} in ${filePath} is missing a 'name' field.")

        String dmqName = entry?.dmq?.toString()?.trim() ?: ""

        List topics = []
        def rawTopics = entry?.topics
        if (rawTopics != null && rawTopics != '') {
            if (!(rawTopics instanceof List))
                errorAndFail("'topics' under queue '${queueName}' in ${filePath} must be a list.")
            rawTopics.eachWithIndex { t, ti ->
                def ts = t?.toString()?.trim()
                if (!ts) errorAndFail("Topic at index ${ti} under queue '${queueName}' in ${filePath} is empty.")
                topics << ts
            }
        }

        if (result.any { it.name == queueName })
            errorAndFail("Duplicate queue name '${queueName}' at index ${idx} in ${filePath}.")

        def dupTopics = topics.countBy { it }.findAll { k, v -> v > 1 }.keySet()
        if (dupTopics)
            errorAndFail("Duplicate topic(s) under queue '${queueName}' in ${filePath}: ${dupTopics}")

        result << [name: queueName, dmq: dmqName, topics: topics]
    }

    if (result.isEmpty()) logWarn("No queue entries found in ${filePath}.")
    return result
}

/**
 * Normalize queue_config block.
 * dead_msg_queue is intentionally NOT in EXPECTED_KEYS —
 * it is declared per-queue via the 'dmq' field in MessageQueue.yaml.
 */
def normalizeQueueConfig(Map data, String filePath) {
    final EXPECTED_KEYS = [
        'ingress_enabled', 'egress_enabled', 'access_type',
        'max_msg_spool_usage', 'owner', 'permission',
        'max_bind_count', 'max_delivered_unacked_msgs_per_flow',
        'delivery_count_enabled', 'delivery_delay',
        'respect_ttl', 'max_ttl',
        'redelivery_enabled', 'max_redelivery_count',
    ]

    def rawCfg = data?.queue_config
    if (rawCfg == null) {
        logWarn("'queue_config' block missing in ${filePath} — all settings will use Solace defaults.")
        rawCfg = [:]
    }
    if (!(rawCfg instanceof Map))
        errorAndFail("'queue_config' in ${filePath} must be a YAML mapping.")

    // Warn if dead_msg_queue is still present — it is ignored
    if (rawCfg.containsKey('dead_msg_queue'))
        logWarn("[${filePath}] 'dead_msg_queue' found in config but is IGNORED. " +
                "Declare DMQ association per-queue via the 'dmq' field in MessageQueue.yaml.")

    def result = [:]
    EXPECTED_KEYS.each { key ->
        def val = rawCfg.containsKey(key) ? rawCfg[key] : null
        if (val == null || val.toString().trim() == '') {
            result[key] = ''
        } else if (val instanceof Boolean) {
            result[key] = val ? 'true' : 'false'
        } else {
            result[key] = val.toString().trim()
        }
        logInfo("  [${filePath}] ${key} = '${result[key]}'")
    }

    def at = result['access_type']
    if (at && !(at in ['exclusive', 'non-exclusive']))
        errorAndFail("[${filePath}] access_type must be 'exclusive' or 'non-exclusive' (or blank). Got: '${at}'")

    def perm = result['permission']
    if (perm && !(perm in ['no-access', 'read-only', 'consume', 'modify-topic', 'delete']))
        errorAndFail("[${filePath}] permission must be one of: no-access, read-only, consume, modify-topic, delete (or blank). Got: '${perm}'")

    ['max_msg_spool_usage', 'max_bind_count', 'max_delivered_unacked_msgs_per_flow',
     'delivery_delay', 'max_ttl', 'max_redelivery_count'].each { k ->
        def v = result[k]
        if (v) {
            try {
                if (v.toLong() < 0) throw new NumberFormatException("negative")
            } catch (NumberFormatException ex) {
                errorAndFail("[${filePath}] '${k}' must be a non-negative integer. Got: '${v}'")
            }
        }
    }

    ['ingress_enabled', 'egress_enabled', 'delivery_count_enabled',
     'respect_ttl', 'redelivery_enabled'].each { k ->
        def v = result[k]
        if (v && !(v in ['true', 'false']))
            errorAndFail("[${filePath}] '${k}' must be true or false (or blank). Got: '${v}'")
    }

    return result
}

/** URL-encode each path segment of a queue/topic name, joining with %2F */
def encodeSegments(String name) {
    return name.split('/').collect { java.net.URLEncoder.encode(it, 'UTF-8') }.join('%2F')
}


// =============================================================================
// LOGGING HELPERS
// =============================================================================

def logSection(String msg) {
    echo ""; echo "=" * 70; echo "  ${msg}"; echo "=" * 70
}
def logInfo(String msg)  { echo "[INFO ] ${msg}" }
def logWarn(String msg)  { echo "[WARN ] ${msg}" }
def logError(String msg) { echo "[ERROR] ${msg}" }

def errorAndFail(String msg) {
    echo "[FATAL] ${msg}"
    error(msg)
}

def shLogged(String cmd, String label) {
    echo "[EXEC ] ${label}"
    sh(label: label, script: cmd)
}

def printSummary() {
    def sep = "=" * 70
    echo ""; echo sep; echo "  OPERATION SUMMARY"; echo sep
    echo "  Job Name         : ${env.JOB_NAME}"
    echo "  Build Number     : ${env.BUILD_NUMBER}"
    echo "  Build URL        : ${env.BUILD_URL}"
    echo "  Repository       : ${params.GITHUB_REPO_URL  ?: 'N/A'}"
    echo "  Branch           : ${params.GITHUB_BRANCH    ?: 'N/A'}"
    echo "  Action           : ${params.TERRAFORM_ACTION ?: 'N/A'}"
    echo "  Message VPN      : ${env.MESSAGE_VPN         ?: 'N/A'}"
    echo "  Regular Queues   : ${env.MQ_COUNT             ?: 'N/A'}"
    echo "  Dead Msg Queues  : ${env.DMQ_COUNT            ?: 'N/A'}"
    echo "  Total Topics     : ${env.TOPIC_COUNT          ?: 'N/A'}"
    if (params.TERRAFORM_ACTION == 'delete-queues') {
        echo "  ── Delete Results ──────────────────────────────────"
        echo "  Deleted        : ${env.DELETE_DELETED ?: '0'}"
        echo "  Skipped (n/a)  : ${env.DELETE_SKIPPED ?: '0'}"
        echo "  Failed         : ${env.DELETE_FAILED  ?: '0'}"
    }
    if (env.TF_OUTPUTS_JSON) {
        try {
            def outputs = readJSON text: env.TF_OUTPUTS_JSON
            echo "  ── Terraform Outputs ───────────────────────────────"
            outputs.each { k, v -> echo "  ${k} : ${v.value}" }
        } catch (_) { /* skip */ }
    }
    echo "  Build Result     : ${currentBuild.currentResult}"
    echo "  Duration         : ${currentBuild.durationString}"
    echo sep; echo ""
}
