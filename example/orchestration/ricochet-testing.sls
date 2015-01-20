Ensure ricochet security group exists:
  boto_secgroup.{{ pillar.orchestration_status }}:
    - name: ricochet
    - description: ricochet
    - rules:
        - ip_protocol: tcp
          from_port: 80
          to_port: 80
          source_group_name: elb
    # If using a vpc, specify the ID for the group
    - vpc_id: {{ pillar.example_profile.vpc_id }}
    - profile: example_profile

Ensure ricochet-testing-useast1 role exists:
  boto_iam_role.{{ pillar.orchestration_status }}:
    - policies:
        'bootstrap':
          Version: '2012-10-17'
          Statement:
            - Action: 'elasticloadbalancing:Describe*'
              Effect: 'Allow'
              Resource:
                - '*'
            - Action:
                - 'elasticloadbalancing:DeregisterInstancesFromLoadBalancer'
                - 'elasticloadbalancing:RegisterInstancesWithLoadBalancer'
              Effect: 'Allow'
              Resource: 'arn:aws:elasticloadbalancing:*:*:loadbalancer/ricochet-testing-iad'
            # Add S3 policy for artifact-based trebuchet mode
            - Action:
                - 's3:Head*'
                - 's3:Get*'
              Effect: 'Allow'
              Resource:
                - 'arn:aws:s3:::bootstrap/deploy/ricochet/*'
            - Action:
                - 's3:List*'
                - 's3:Get*'
              Effect: 'Allow'
              Resource:
                - 'arn:aws:s3:::bootstrap'
              Condition:
                StringLike:
                  's3:prefix':
                    - 'deploy/ricochet/*'
            - Action:
                - 'ec2:DescribeTags'
              Effect: 'Allow'
              Resource:
                - '*'
    - name: ricochet-testing-useast1
    - profile: example_profile

Ensure ricochet-testing-iad elb exists:
  boto_elb.present:
    - name: ricochet-testing-iad
    - listeners:
        - elb_port: 80
          instance_port: 80
          elb_protocol: HTTP
    - health_check:
        target: 'HTTP:80/'
    - subnets:
      {% for subnet in pillar.example_profile.vpc_subnets %}
      - {{ subnet }}
      {% endfor %}
    # Security groups on ELBs are VPC only
    - security_groups:
        - elb
    - attributes: []
    - cnames:
        - name: ricochet-testing.{{ pillar.domain }}.
          zone: {{ pillar.domain }}.
    - profile: example_profile

Ensure ricochet-testing-useast1 asg exists:
  boto_asg.{{ pillar.orchestration_status }}:
    - name: ricochet-testing-useast1
    {% if pillar.orchestration_status == 'absent' %}
    - force: True
    {% endif %}
    - launch_config_name: ricochet-testing-useast1
    - launch_config:
      # Free tier eligible AMI, Ubuntu 14.04
      - image_id: ami-864d84ee
      - key_name: {{ pillar.example_profile.key_name }}
      - security_groups:
        - base
        - ricochet
      # The instance profile name used here should match the instance profile
      # created above.
      - instance_profile_name: ricochet-testing-useast1
      - instance_type: t2.micro
      # Use a public ip, if in a vpc
      - associate_public_ip_address: True
      - cloud_init:
          scripts:
            salt: |
              #!/bin/bash
              apt-get -y update
              apt-get install -y build-essential libssl-dev python-dev python-m2crypto \
              python-pip python-virtualenv python-zmq python-crypto swig virtualenvwrapper \
              git-core
              
              mkdir -p /srv/salt/venv
              virtualenv --system-site-packages /srv/salt/venv
              git clone -b add-example https://github.com/trebuchet-deploy/trebuchet.git /srv/trebuchet
              . /srv/salt/venv/bin/activate
              pip install -r /srv/trebuchet/requirements.txt
              deactivate
              export DOMAIN="{{ pillar['domain'] }}"
              /srv/salt/venv/bin/salt-call --local -c /srv/trebuchet/example/states/common/salt state.sls bootstrap
              /srv/salt/venv/bin/salt-call state.highstate
    - vpc_zone_identifier:
      {% for subnet in pillar.example_profile.vpc_subnets %}
      - {{ subnet }}
      {% endfor %}
    - availability_zones:
      - us-east-1a
      - us-east-1d
      - us-east-1e
    - load_balancers:
      - ricochet-testing-iad
    - min_size: 1
    - max_size: 1
    - desired_capacity: 1
    - tags:
      # Adding a name tag makes it easier to identify the ASG nodes in the
      # instances list.
      - key: 'Name'
        value: 'ricochet-testing-useast1'
        propagate_at_launch: true
    - profile: example_profile
