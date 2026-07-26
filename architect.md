# Kafka-Based Microservices Architecture (AWS + Kubernetes + GitHub Actions + Terraform)

This is a realistic **senior DevOps engineer architecture** that you can confidently explain in interviews. It combines the technologies from your resume (AWS, Kubernetes, Terraform, Docker, GitHub Actions, Kafka).

---

```md
# Event Driven Microservices Architecture

                                   +----------------------+
                                   |      End User        |
                                   +----------+-----------+
                                              |
                                              |
                                        HTTPS Request
                                              |
                                              |
                                  +-----------v------------+
                                  |    AWS Route53 DNS     |
                                  +-----------+------------+
                                              |
                                              |
                                  +-----------v------------+
                                  | AWS Application Load   |
                                  | Balancer (ALB)         |
                                  +-----------+------------+
                                              |
                                   Kubernetes Ingress
                                              |
                    -------------------------------------------------
                    |                     |                        |
                    |                     |                        |
            +-------v------+      +-------v------+        +--------v-------+
            | Order Service|      | User Service |        | Payment Service|
            | Deployment   |      | Deployment   |        | Deployment     |
            +-------+------+      +-------+------+        +--------+-------+
                    |                     |                         |
                    |                     |                         |
            Business Logic        Business Logic            Business Logic
                    |                     |                         |
                    +----------+----------+-------------------------+
                               |
                               |
                       Publish Event
                               |
                               |
                 +-------------v--------------+
                 | Kafka Producer Library     |
                 +-------------+--------------+
                               |
                               |
                  -------------------------------
                  |                             |
        Kafka Broker-1                 Kafka Broker-2
        (Leader Partition)            (Follower Replica)
                  |                             |
                  -----------Replication---------
                               |
                        Kafka Topic
                         OrderCreated
                               |
                 ---------------------------------
                 |               |               |
                 |               |               |
        Inventory Consumer  Email Consumer  Analytics Consumer
                 |               |               |
                 |               |               |
          Update DB         Send Email      Store Metrics
                 |               |               |
            PostgreSQL      SES/SNS         S3/Redshift

```

---

# Infrastructure Provisioning

```
Terraform

├── modules
│      ├── networking
│      │      ├── VPC
│      │      ├── Public Subnets
│      │      ├── Private Subnets
│      │      ├── NAT Gateway
│      │      ├── Route Tables
│      │      └── Security Groups
│
│      ├── eks
│      │      ├── Control Plane
│      │      ├── Worker Nodes
│      │      └── IAM Roles
│
│      ├── kafka
│      │      ├── EC2 Instances
│      │      ├── EBS Storage
│      │      ├── ZooKeeper
│      │      └── Kafka Brokers
│
│      ├── database
│      ├── alb
│      ├── iam
│      └── monitoring
│
└── environments
       ├── dev
       ├── qa
       └── prod

```

Terraform provisions

* VPC
* Private/Public Subnets
* EKS Cluster
* Kafka EC2 instances
* Security Groups
* IAM Roles
* ALB
* RDS
* S3
* CloudWatch

---

# CI/CD Flow (GitHub Actions)

```
Developer

     |

Git Push

     |

GitHub Repository

     |

GitHub Actions Trigger

     |

Checkout Source

     |

Run Unit Tests

     |

SonarQube Scan

     |

Build Docker Image

     |

Push Image to Amazon ECR

     |

Terraform Plan

     |

Terraform Apply

     |

kubectl Apply / Helm Upgrade

     |

Pods Updated inside EKS

```

---

# Kubernetes Architecture

```
                     Kubernetes Cluster

------------------------------------------------------------

Namespace : production

Ingress Controller

        |

Service

        |

Deployment

        |

ReplicaSet

        |

Pods

Order Service (3 replicas)

Payment Service (3 replicas)

Inventory Service (2 replicas)

Notification Service (2 replicas)

------------------------------------------------------------

Kafka Broker Pods (or EC2)

------------------------------------------------------------

Persistent Volume

------------------------------------------------------------

```

---

# Complete Business Flow

Suppose a customer places an order.

## Step 1

User clicks

```
Place Order
```

Browser sends request

```
POST /orders
```

to

```
ALB
```

---

## Step 2

ALB forwards request

```
Ingress

↓

Order Service Pod
```

---

## Step 3

Order Service validates

* User
* Inventory
* Payment Information

---

## Step 4

Order Service saves order

```
Orders Table

OrderID = 101
Status = Created
```

---

## Step 5

Instead of calling Inventory Service directly,

Order Service publishes

```
Topic

OrderCreated
```

Message

```json
{
  "orderId":101,
  "customerId":5001,
  "product":"Laptop",
  "quantity":1
}
```

---

## Step 6

Kafka Broker receives

Producer

↓

Broker

↓

Topic

↓

Partition

↓

Replication

---

## Step 7

Consumers subscribe

Inventory Service

```
Consumes OrderCreated
```

Reserves inventory.

---

Payment Service

Consumes

```
OrderCreated
```

Charges customer.

---

Notification Service

Consumes

```
OrderCreated
```

Sends email.

---

Analytics Service

Consumes

```
OrderCreated
```

Stores metrics.

---

Notice

All four services consume the SAME message independently.

No service waits for another.

---

# Kafka Internal Flow

```
Producer

↓

Serializer

↓

Partitioner

↓

Kafka Broker Leader

↓

Follower Replica

↓

Consumer Group

↓

Consumer

```

---

# Producer Configuration

Producer knows

```
bootstrap.servers

broker1:9092
broker2:9092
```

Producer doesn't know where partition lives.

Broker metadata tells producer.

---

# Topic Example

```
Topic

OrderCreated

Partitions

0

1

2

Replication Factor

2

```

Partition example

```
Partition 0

Order101

Order105

Order120

Partition 1

Order102

Order106

Partition 2

Order103

Order107

```

---

# Why Partitions?

Allows

```
Parallel Processing
```

Three consumers can process three partitions simultaneously.

---

# Consumer Groups

```
Consumer Group

Inventory

Consumer A

Consumer B

Consumer C
```

Kafka assigns

```
Partition0 -> ConsumerA

Partition1 -> ConsumerB

Partition2 -> ConsumerC
```

No duplicate processing.

---

# Offset

Kafka stores

```
Offset

0

1

2

3

4
```

Consumer processed until

```
Offset = 200
```

If pod crashes,

new pod resumes from

```
Offset 201
```

No data loss.

---

# Deployment Flow

```
Developer

↓

GitHub

↓

GitHub Actions

↓

Docker Build

↓

Push to Amazon ECR

↓

kubectl rollout

↓

New Pods

↓

Pods connect to Kafka

↓

Kafka Producers

↓

Kafka Consumers

↓

Business Processing

```

---

# How Microservices Connect to Kafka

Inside Kubernetes

Every pod has environment variables:

```
KAFKA_BOOTSTRAP_SERVERS

broker1:9092,broker2:9092
```

Application code

```
Producer

↓

Kafka Client Library

↓

Broker
```

Consumer

```
Broker

↓

Kafka Client

↓

Application
```

No service talks directly to another service for event-driven workflows.

---

# Monitoring

CloudWatch

* EC2 metrics
* EKS metrics
* ALB metrics

Prometheus

* Kafka lag
* Consumer lag
* Broker health

Grafana

* Dashboards
* Topic throughput
* Partition utilisation

Logs

Application Logs

↓

Fluent Bit

↓

CloudWatch Logs

---

# High Availability

Kafka

```
Broker1

Leader
```

```
Broker2

Follower
```

If Broker1 fails

↓

Broker2 becomes Leader automatically.

Consumers continue reading.

---

# Security

* TLS encryption between producers, brokers, and consumers.
* SASL/SCRAM or IAM-based authentication (for managed Kafka) to verify clients.
* Kubernetes Secrets (or CyberArk integrated with External Secrets) store Kafka credentials instead of hardcoding them.
* Network policies and security groups restrict Kafka access to only authorised applications.

---

# Interview Summary (30-Second Explanation)

> "We used Terraform to provision the AWS infrastructure, including the VPC, EKS cluster, Kafka brokers, ALB, and supporting services. Developers pushed code to GitHub, which triggered GitHub Actions to run tests, perform SonarQube analysis, build Docker images, push them to Amazon ECR, and deploy updated workloads to Kubernetes using Helm or `kubectl`. Business requests entered through the ALB and Ingress Controller to the appropriate microservice. Instead of synchronous service-to-service calls, services published business events such as `OrderCreated` to Kafka topics. Kafka replicated these events across brokers for fault tolerance, and multiple consumer services—such as Inventory, Payment, Notification, and Analytics—processed the same event independently. This event-driven architecture improved scalability, resiliency, and decoupling while Kubernetes handled auto-scaling and self-healing, and Prometheus, Grafana, and CloudWatch provided end-to-end monitoring."
    