# PGPool

访问 Postgresql 数据库的 Elixir 模块

## Installation

  1. 在 `mix.exs` 的依赖中添加 `pgpool`

        def deps do
          [{:pgpool, git: "git@gitlab.ruicloud.cn:titan/pgpool.git", branch: "master" }]
        end

  2. 确认 `pgpool` 在应用前启动:

        def application do
          [applications: [:pgpool]]
        end

  3. 配置文件中加入：

        config :pgpool,
        databases: [
            {:mydbname,
            [
                size: 10,
                max_overflow: 20
            ],
            [
                hostname: 'localhost',
                database: 'xxx',
                username: 'xxx',
                password: 'xxx'
            ]
            }
        ]
