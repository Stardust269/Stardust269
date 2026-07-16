# 非信贷交易信息概要(lj_iceberg.pboccr2d.dsst_eds_gaa02_common_trans_summary)
page_id: 39c617cf-3593-80c2-877e-c55f70ba9320


| 字段解释 | 备份 | 字段名称 | 数值类型 | 字段编码 |
| 自增主键ID |  | 主键ID | long | id |
| 报告ID |  | 报告ID | varchar(32) | id_unqf |
| 客户ID |  | 客户ID | varchar(32) | id_unqp |
| 后付费业务类型 | 对应字典表：fee_delay_type_code | 后付费业务类型 | varchar(32) | fee_delay_type |
| 欠费账户数 |  | 欠费账户数 | short(8) | arrears_account_num |
| 欠费金额 |  | 欠费金额 | int | arrears_amount |
| 插入时间 |  | 插入时间 | datatime | time_inst |