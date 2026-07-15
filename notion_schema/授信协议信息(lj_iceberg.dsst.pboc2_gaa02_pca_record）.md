# 授信协议信息(lj_iceberg.dsst.pboc2_gaa02_pca_record）
page_id: 39c617cf-3593-80ee-aef3-e4bf5eda3b71


| 字段编码 | 字段解释 | 字段名称 | 备注 | 数值类型 |
| id | 自增主键ID | 主键ID |  | long |
| id_unqf | 报告ID | 报告ID |  | varchar(32) |
| id_unqp | 客户ID | 客户ID |  | varchar(32) |
| credit_serial_no | 授信协议编号 | 授信协议编号 |  | varchar(32) |
| org_name | 业务管理机构 | 业务管理机构 |  | varchar(16) |
| identification | 授信协议标识 | 授信协议标识 |  | varchar(32) |
| start_date | 生效日期 | 生效日期 |  | date |
| end_date | 到期日期 | 到期日期 |  | date |
| credit_purpose | 授信额度用途 | 授信额度用途 | 对应字典：pcredit_purpose_code | varchar(16) |
| credit_amount | 授信额度 | 授信额度 |  | int |
| limit_amount | 授信限额 | 授信限额 |  | int |
| limit_no | 授信限额编号 | 授信限额编号 |  | varchar(64) |
| use_amount | 已用额度 | 已用额度 |  | int |
| currency_type | 币种 | 币种 | 对应字典：币种 | varchar(16) |
| busi_org_type | 业务管理机构类型 | 业务管理机构类型 | 对应字典：institution_type_code | varchar(16) |
| status | 授信协议状态 | 授信协议状态 | 对应字典：pcredit_state_code | varchar(16) |
| time_inst | 插入时间 | 插入时间 |  | datetime |
可直接用于模型训练的特征共4项：
授信使用率（use_amount / credit_amount）→ 核心负债压力指标；
协议剩余天数（end_date - 当前日期）→ 需求紧迫性指标；
协议状态标识（二值化：即将到期/部分使用中=1，否则=0）→ 需求场景标识；
短期用途标识（二值化：短期周转类=1，否则=0）→ 需求延续性指标。