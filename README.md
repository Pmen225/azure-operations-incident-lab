# Azure monitoring and alerting

[![Source validation](https://github.com/Pmen225/azure-operations-incident-lab/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/Pmen225/azure-operations-incident-lab/actions/workflows/validate.yml)

Terraform configuration for Linux VM monitoring with Azure Monitor Agent, Log Analytics, Syslog collection and a CPU metric alert. The repository also contains a bounded CPU load script with process lifecycle tests. The default resources use UK South and a Standard_B2s Ubuntu 22.04 VM.

## Architecture

```text
Private VM -> NAT gateway -> Azure Monitor Agent endpoints -> Log Analytics
    |
    +-> Azure platform Percentage CPU metric -> alert -> Action Group

Administrator -> Azure Run Command -> VM agent
```

The VM has a system assigned identity and no public IP. A subnet NSG denies inbound connections, including SSH. Administration uses Azure Run Command. Explicit NAT egress supports extension downloads, agent communication and telemetry; it does not filter outbound destinations.

## Monitoring configuration

The Data Collection Rule collects Syslog at Warning, Error, Critical, Alert and Emergency levels from the `auth`, `authpriv`, `daemon` and `syslog` facilities. Records are routed to a Log Analytics workspace with 30 day retention.

CPU alerting uses the Azure platform `Percentage CPU` metric independently of Syslog. A severity 2 alert evaluates every minute and triggers when average CPU exceeds 80% over five minutes. High CPU alone does not produce a Syslog record, and the DCR does not collect guest performance counters.

An Action Group is attached to the metric alert. It has no notification receiver by default. The optional `alert_email` input adds an email recipient; alert delivery depends on that configuration and live service behaviour.

## Bounded load script

The Bash script defaults to two worker processes for 420 seconds, with maximum inputs of 64 workers and 1,800 seconds. It records its own process IDs and stops those workers on normal completion or a catchable interrupt or termination signal. It does not stop unrelated processes, restart services or change VM sizing.

The script is intended for a disposable VM authorised for load testing. Terraform and CI do not run CPU load. Python regression tests substitute sleeping processes to check invalid arguments, timeout, signal handling and preservation of unrelated processes.

## Validation

GitHub Actions checks Terraform formatting, locked provider initialisation, schema validation, Bash syntax and the Python lifecycle tests without Azure credentials. The badge reports the latest workflow status on `main`.

The process tests cover argument validation, automatic timeout and cleanup behaviour. Azure telemetry collection and alert delivery depend on the deployed resource configuration.

## Design and operations

Standard_B2s is burstable, so available CPU credits can affect whether a sustained load reaches the alert threshold. Action Run Command executes with elevated privileges, supports one script at a time and cannot cancel an active request through that API. The load duration is therefore bounded within the script.

Terraform uses local state. Subscription permissions, resource provider registration and regional capacity remain deployment dependencies. State and saved plans can contain sensitive values and are excluded from version control.

VM compute, disks, NAT gateway, public IP and log ingestion can incur charges. Stopping the VM does not remove all resource costs. Remediation remains an operator controlled action.

## Source layout

- [`infra/`](infra/): VM, networking, telemetry collection and alert definitions
- [`scripts/generate-cpu.sh`](scripts/generate-cpu.sh): bounded load generation
- [`tests/`](tests/): process lifecycle regression tests
- [Validation workflow](.github/workflows/validate.yml): automated source checks
