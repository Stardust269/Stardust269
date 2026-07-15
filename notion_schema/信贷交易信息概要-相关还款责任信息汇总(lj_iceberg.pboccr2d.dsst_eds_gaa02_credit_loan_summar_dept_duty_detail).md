# 信贷交易信息概要-相关还款责任信息汇总(lj_iceberg.pboccr2d.dsst_eds_gaa02_credit_loan_summar_dept_duty_detail)
page_id: 39c617cf-3593-8038-8a52-f4491ee8edba


| 字段解释 | 数值类型 | 字段编码 | 备注 | 字段名称 |
| 自增主键ID | long | id |  | 主键ID |
| 报告ID | varchar(32) | id_unqf |  | 报告ID |
| 客户ID | varchar(32) | id_unqp |  | 客户ID |
| 借款人身份类别 | varchar(8) | ptype | 对应字典：identity_type_code | 借款人身份类别 |
| 担保责任;其他相关还款责任 | varchar(8) | loan_repay_liability_type | 对应字典：loan_repay_liability_type_code | 还款责任类型 |
| 账户数 | int | acount_num |  | 账户数 |
| 还款责任金额 | int | debt_duty_amount |  | 还款责任金额 |
| 余额 | int | balance |  | 余额 |
| 插入时间 | datatime | time_inst |  | 插入时间 |