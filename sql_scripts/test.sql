    -- E-commerce Inventory and Order Management System
    -- Testing Script
    -- ===================================================

-- Use the database
USE EcommerceSystem;
GO

-- Clear existing data for testing (if needed)
DELETE FROM InventoryLogs;
DELETE FROM OrderDetails;
DELETE FROM Orders;
DELETE FROM Products;
DELETE FROM Customers;
GO

-- Reset identity columns
DBCC CHECKIDENT ('InventoryLogs', RESEED, 0);
DBCC CHECKIDENT ('OrderDetails', RESEED, 0);
DBCC CHECKIDENT ('Orders', RESEED, 0);
DBCC CHECKIDENT ('Products', RESEED, 0);
DBCC CHECKIDENT ('Customers', RESEED, 0);
GO

-- 1. Test Product Creation
PRINT '1. Testing Product Creation';

-- Add test products
EXEC sp_AddProduct 'Smartphone X', 'Electronics', 799.99, 100, 20;
EXEC sp_AddProduct 'Wireless Earbuds', 'Electronics', 129.99, 200, 30;
EXEC sp_AddProduct 'Laptop Pro', 'Electronics', 1299.99, 50, 10;
EXEC sp_AddProduct 'Coffee Maker', 'Home Appliances', 89.99, 75, 15;
EXEC sp_AddProduct 'Blender', 'Home Appliances', 59.99, 100, 20;
EXEC sp_AddProduct 'Gaming Mouse', 'Computing', 49.99, 150, 25;
EXEC sp_AddProduct 'Mechanical Keyboard', 'Computing', 129.99, 80, 15;
EXEC sp_AddProduct 'Desk Chair', 'Furniture', 249.99, 30, 5;
EXEC sp_AddProduct 'Office Desk', 'Furniture', 349.99, 20, 5;
EXEC sp_AddProduct 'Tablet Pro', 'Electronics', 699.99, 5, 10;  -- Low stock example

-- Verify products were added correctly
SELECT * FROM Products;
SELECT * FROM InventoryLogs;

-- 2. Test Customer Creation
PRINT '2. Testing Customer Creation';

-- Add test customers
INSERT INTO Customers (CustomerName, Email, Phone)
VALUES 
    ('John Smith', 'john.smith@example.com', '555-123-4567'),
    ('Jane Doe', 'jane.doe@example.com', '555-234-5678'),
    ('Robert Johnson', 'robert.johnson@example.com', '555-345-6789'),
    ('Sarah Williams', 'sarah.williams@example.com', '555-456-7890'),
    ('Michael Brown', 'michael.brown@example.com', '555-567-8901');

-- Verify customers were added correctly
SELECT * FROM Customers;

-- 3. Test Order Creation and Inventory Updates
PRINT '3. Testing Order Creation and Inventory Updates';

-- Create order items table variable
DECLARE @OrderItems1 OrderItemsTableType;
INSERT INTO @OrderItems1 (ProductID, Quantity) VALUES (1, 2), (2, 1), (4, 1);

-- Create first order
EXEC sp_CreateOrder 1, @OrderItems1;

-- Verify order was created
SELECT * FROM Orders;
SELECT * FROM OrderDetails;

-- Verify stock was updated
SELECT * FROM Products WHERE ProductID IN (1, 2, 4);

-- Verify inventory logs were created
SELECT * FROM InventoryLogs WHERE ProductID IN (1, 2, 4) AND ChangeType = 'Order';

-- Create more orders to test customer tiers
DECLARE @OrderItems2 OrderItemsTableType;
INSERT INTO @OrderItems2 (ProductID, Quantity) VALUES (3, 1), (9, 1);  -- Expensive items

-- Create second order for customer 1 (to reach Silver tier)
EXEC sp_CreateOrder 1, @OrderItems2;

-- Create large order for customer 2 (to reach Gold tier)
DECLARE @OrderItems3 OrderItemsTableType;
INSERT INTO @OrderItems3 (ProductID, Quantity) VALUES (3, 4), (1, 2);  -- Multiple expensive laptops

EXEC sp_CreateOrder 2, @OrderItems3;

-- Create huge order for customer 3 (to reach Platinum tier)
DECLARE @OrderItems4 OrderItemsTableType;
INSERT INTO @OrderItems4 (ProductID, Quantity) VALUES (3, 8);  -- Many expensive laptops

EXEC sp_CreateOrder 3, @OrderItems4;

-- Verify customer tiers were updated
SELECT CustomerID, CustomerName, CustomerTier FROM Customers;

-- 4. Test Bulk Order with Discounts
PRINT '4. Testing Bulk Order with Discounts';

-- Create bulk order item table variable (to test discounts)
DECLARE @BulkOrderItems OrderItemsTableType;
INSERT INTO @BulkOrderItems (ProductID, Quantity) VALUES (6, 25);  -- 25 gaming mice (should get 10% discount)

-- Create bulk order
EXEC sp_CreateOrder 4, @BulkOrderItems;

-- Verify discount was applied
SELECT o.OrderID, o.TotalAmount, od.Quantity, od.UnitPrice, od.Discount,
       (od.UnitPrice * od.Quantity * (1 - od.Discount/100)) AS DiscountedTotal
FROM Orders o
JOIN OrderDetails od ON o.OrderID = od.OrderID
WHERE o.CustomerID = 4;

-- 5. Test Stock Replenishment
PRINT '5. Testing Stock Replenishment';

-- Check current stock levels
SELECT * FROM vw_ProductStockStatus;

-- Replenish stock for products with low stock
EXEC sp_ReplenishStock 10, 20;  -- Replenish Tablet Pro that was low in stock

-- Check updated stock levels
SELECT * FROM Products WHERE ProductID = 10;

-- Check inventory logs for replenishment
SELECT * FROM InventoryLogs WHERE ProductID = 10 AND ChangeType = 'Replenishment';

-- 6. Test Stock Level Monitoring
PRINT '6. Testing Stock Level Monitoring';

-- Get products that need replenishment
EXEC sp_CheckStockLevels;

-- 7. Test Order Summary View
PRINT '7. Testing Order Summary View';

-- Get order summaries
SELECT * FROM vw_OrderSummary;

-- 8. Test Product Stock Status View
PRINT '8. Testing Product Stock Status View';

-- Get product stock status
SELECT * FROM vw_ProductStockStatus;

-- 9. Test Customer Spending Summary View
PRINT '9. Testing Customer Spending Summary View';

-- Get customer spending summaries
SELECT * FROM vw_CustomerSpendingSummary;

-- 10. Test Inventory Change History View
PRINT '10. Testing Inventory Change History View';

-- Get inventory change history
SELECT * FROM vw_InventoryChangeHistory;

-- 11. Test Handling of Insufficient Stock
PRINT '11. Testing Handling of Insufficient Stock';

-- Try to place an order with insufficient stock
DECLARE @InsufficientStockOrder OrderItemsTableType;
INSERT INTO @InsufficientStockOrder (ProductID, Quantity) VALUES (3, 100);  -- Try to order 100 laptops (only ~42 left)

-- This should fail with an error about insufficient stock
BEGIN TRY
    EXEC sp_CreateOrder 5, @InsufficientStockOrder;
END TRY
BEGIN CATCH
    SELECT 
        ERROR_NUMBER() AS ErrorNumber,
        ERROR_MESSAGE() AS ErrorMessage;
END CATCH;

-- 12. Test Different Product Categories Analytics
PRINT '12. Testing Product Categories Analytics';

-- Get sales by product category
SELECT 
    p.Category,
    COUNT(DISTINCT o.OrderID) AS TotalOrders,
    SUM(od.Quantity) AS TotalQuantitySold,
    SUM(od.UnitPrice * od.Quantity * (1 - od.Discount/100)) AS TotalRevenue
FROM Products p
JOIN OrderDetails od ON p.ProductID = od.ProductID
JOIN Orders o ON od.OrderID = o.OrderID
GROUP BY p.Category
ORDER BY TotalRevenue DESC;

-- Report on inventory values by category
SELECT 
    Category,
    COUNT(*) AS ProductCount,
    SUM(StockQuantity) AS TotalStock,
    SUM(StockQuantity * Price) AS InventoryValue
FROM Products
GROUP BY Category
ORDER BY InventoryValue DESC;

-- 13. Testing Comprehensive Order Details
PRINT '13. Testing Comprehensive Order Details';

-- Get detailed order information for a specific customer
DECLARE @TestCustomerID INT = 1;

SELECT 
    o.OrderID,
    o.OrderDate,
    o.TotalAmount,
    p.ProductName,
    od.Quantity,
    od.UnitPrice,
    od.Discount,
    (od.Quantity * od.UnitPrice * (1 - od.Discount/100)) AS LineTotal
FROM Orders o
JOIN OrderDetails od ON o.OrderID = od.OrderID
JOIN Products p ON od.ProductID = p.ProductID
WHERE o.CustomerID = @TestCustomerID
ORDER BY o.OrderDate DESC, o.OrderID;

-- Print summary of test results
PRINT '--- Test Summary ---';
SELECT 
    (SELECT COUNT(*) FROM Products) AS TotalProducts,
    (SELECT COUNT(*) FROM Customers) AS TotalCustomers,
    (SELECT COUNT(*) FROM Orders) AS TotalOrders,
    (SELECT COUNT(*) FROM OrderDetails) AS TotalOrderDetails,
    (SELECT COUNT(*) FROM InventoryLogs) AS TotalInventoryLogs;

-- Test customer tier assignment accuracy
SELECT 
    CustomerTier,
    COUNT(*) AS CustomerCount
FROM Customers
GROUP BY CustomerTier
ORDER BY 
    CASE CustomerTier 
        WHEN 'Bronze' THEN 1
        WHEN 'Silver' THEN 2
        WHEN 'Gold' THEN 3
        WHEN 'Platinum' THEN 4
    END;