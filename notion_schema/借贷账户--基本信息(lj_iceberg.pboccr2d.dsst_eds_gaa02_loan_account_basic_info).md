# 借贷账户--基本信息(lj_iceberg.pboccr2d.dsst_eds_gaa02_loan_account_basic_info)
page_id: 39c617cf-3593-80f2-a335-ffc7e9b5cda6


| 字段名称 | 备注 | 字段编码 | 字段解释 | 数值类型 |
| 主键ID |  | id | 自增主键ID | long |
| 报告ID |  | id_unqf | 报告ID | varchar(32) |
| 客户ID |  | id_unqp | 客户ID | varchar(32) |
| 账户编号 |  | account_no | 账户编号 | varchar(32) |
| 授权协议编号 |  | credit_serial_no | 征信系统分配给该协议在本报告中的唯一编号 | varchar(32) |
| 账户类型 | 对应字典：loan_account_type_code | account_type | 账户类型（枚举） | varchar(16) |
| 业务管理机构类型 | 对应字典：institution_type_code | org_manage_type | 业务管理机构类型(枚举) | varchar(16) |
| 业务管理机构代码 |  | org_manage_code | 业务管理机构代码 数据提供机构内部具体负责借款人账户管理、信息核 实和相关异议处理的网点 /分支机构在征信系统中的 唯一编码。 | varchar(32) |
| 账户标识 |  | account_id | 账户标识在征信系统全局范围内用于唯一识别一个借贷账户的标识码 | varchar(60) |
| 开立日期 |  | open_date | 开立日期 | date |
| 到期日期 |  | end_date | 到期日期 | date |
| 借款金额 |  | loan_amount | 借款金额 | int(15) |
| 币种 | 对应字典：对应币种字典表 | currency_type | 币种(枚举) | varchar(16) |
| 业务种类 | 对应字典：loan_business_type_code | busi_type | 业务种类(枚举) | varchar(32) |
| 担保方式 | 对应字典：loan_business_guarantee_type_code | assure_type | 担保方式(枚举) | varchar(16) |
| 还款期数 |  | payment_payment | 还款期数 | short(3) |
| 还款频率 |  | payment_frequency | 还款频率 | varchar(16) |
| 还款方式 | 对应字典：loan_repayment_type_code | payment_type | 还款方式(枚举) | varchar(16) |
| 共同借款标识 | 对应字典：ploan_coborrower_mark_code | loan_together_state | 共同借款状态(枚举) | varchar(16) |
| 账户授信额度 |  | credit_grant_amount | 账户授信额度 | int(15) |
| 共享授信额度 |  | share_credit_amount | 共享授信额度 | int(15) |
| 贷款发放形式 | 对应字典：loan_payment_type_code | loan_give_type | 贷款发放形式(枚举) | varchar(16) |
| 债权转移时的还款状态 | 对应字典：repayment_transfer_debt_state_code | payment_state_transfer | 债权转移时的还款状态(枚举) | varchar(16) |
| 插入时间 |  | time_inst | 插入时间 | datatime |