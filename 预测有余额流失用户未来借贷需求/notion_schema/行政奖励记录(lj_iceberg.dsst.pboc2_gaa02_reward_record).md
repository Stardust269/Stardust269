# 行政奖励记录(lj_iceberg.dsst.pboc2_gaa02_reward_record)
page_id: 39c617cf-3593-802b-a1a3-caa404cea36e


| 征信报告数据获取来源 | 字段名称 | 字段解释 | 数值类型 | 字段编码 |
|  | 主键ID | 自增主键ID | long | id |
|  | 报告ID | 报告ID | varchar(32) | id_unqf |
|  | 客户ID | 客户ID | varchar(32) | id_unqp |
|  | 编号 | 编号 | varchar(32) | no_reward |
|  | 奖励机构 | 奖励机构 | varchar(32) | reward_org |
|  | 奖励内容 | 奖励内容 | varchar(128) | reward_content |
|  | 生效日期 | 生效日期 | date | start_date |
|  | 截止日期 | 截止日期 | date | end_date |
|  | 插入时间 | 插入时间 | datetime | time_inst |