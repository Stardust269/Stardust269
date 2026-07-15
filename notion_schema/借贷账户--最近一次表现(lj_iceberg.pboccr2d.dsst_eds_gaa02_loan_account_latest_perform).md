# 借贷账户--最近一次表现(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_latest_perform)
page_id: 39c617cf-3593-80d8-9d14-d5ce00e005d2


| 数值类型 | 字段解释 | 备注 | 字段编码 | 字段名称 |
| long | 自增主键ID |  | id | 主键ID |
| varchar(32) | 报告ID |  | id_unqf | 报告ID |
| varchar(32) | 客户ID |  | id_unqp | 客户ID |
| varchar(60) | 账户标识 |  | account_id | 账户标识 |
| varchar(16) | 账户状态(枚举) | 对应字典：D1账户：ploan_d1_account_state_codeR1账户：ploan_r1_account_state_codeR2R3账户：ploan_r2r3_account_state_codeR4账户：ploan_r4_account_state_codeC1账户：ploan_c1_account_state_code | account_state | 账户状态 |
| date | 关闭日期 |  | close_date | 关闭日期 |
| varchar(16) | 转出年月 | yyyy-mm | turn_out_date | 转出年月 |
| int | 余额 |  | balance | 余额 |
| date | 最近一次还款日期 |  | latest_repayment_date | 最近一次还款日期 |
| int | 最近一次还款金额 |  | latest_repayment_amount | 最近一次还款金额 |
| varchar(16) | 贷款五级分类(枚举) | 对应字典：risk_account_level | level5_type | 五级分类 |
| varchar(16) | 还款状态(枚举) | 对应字典：repayment_D1R4_state_coderepayment_R1_state_coderepayment_R3_state_coderepayment_R3_state_code | repayment_state | 还款状态 |
| date | 信息报告日期 |  | info_date | 信息报告日期 |
| datatime | 插入时间 |  | time_inst | 插入时间 |