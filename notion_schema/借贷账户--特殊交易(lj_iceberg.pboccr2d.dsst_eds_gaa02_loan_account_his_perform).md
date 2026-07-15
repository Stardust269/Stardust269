# 借贷账户--特殊交易(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_his_perform)
page_id: 39c617cf-3593-8049-9d3a-fcf2839052e5


| 字段名称 | 数值类型 | 备注 | 字段解释 | 字段编码 |
| 主键ID | long |  | 自增主键ID | id |
| 报告ID | varchar(32) |  | 报告ID | id_unqf |
| 客户ID | varchar(32) |  | 客户ID | id_unqp |
| 账户标识 | varchar(60) |  | 账户标识 | account_no |
| 特殊交易类型 | varchar(16) | 对应字典：pls_trade_type_code | 特殊交易类型 | strans_type |
| 特殊交易发生日期 | date |  | 反映特殊交易发生的日期 | strans_date |
| 到期日期变更月数 | short |  | 特殊交易引起的到期日变更月数 | strans_month_update_num |
| 特殊交易发生金额 | int(15) |  | 反映特殊交易相应的发生金额 | strans_amount |
| 特殊交易明细记录 | varchar(256) |  | 特殊交易详细情况的描述 | strans_des |
| 插入时间 | datatime |  | 插入时间 | time_inst |