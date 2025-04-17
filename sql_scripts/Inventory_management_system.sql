    -- E-commerce Inventory and Order Management System
    --=================================================

-- --Switch to the main database
-- USE MASTER;
-- -- Create database 
-- GO
-- CREATE DATABASE EcommerceSystem;
-- GO
-- --Switch to the newly created "EcommerceSystem" database
-- USE EcommerceSystem;

 GO

-- Create tables
CREATE TABLE Products (
    ProductID INT PRIMARY KEY IDENTITY(1,1),
    ProductName NVARCHAR(100) NOT NULL,
    Category NVARCHAR(50) NOT NULL,
    Price DECIMAL(10, 2) NOT NULL CHECK (Price >= 0),
    StockQuantity INT NOT NULL DEFAULT 0 CHECK (StockQuantity >= 0),
    ReorderLevel INT NOT NULL DEFAULT 10 CHECK (ReorderLevel >= 0)
);

CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY IDENTITY(1,1),
    CustomerName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(100) NOT NULL UNIQUE,
    Phone NVARCHAR(20),
    CustomerTier NVARCHAR(20) DEFAULT 'Bronze' CHECK (CustomerTier IN ('Bronze', 'Silver', 'Gold', 'Platinum'))
);

CREATE TABLE Orders (
    OrderID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL,
    OrderDate DATETIME NOT NULL DEFAULT GETDATE(),
    TotalAmount DECIMAL(12, 2) NOT NULL DEFAULT 0,
    Status NVARCHAR(20) DEFAULT 'Pending' CHECK (Status IN ('Pending', 'Processing', 'Shipped', 'Delivered', 'Cancelled')),
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);

CREATE TABLE OrderDetails (
    OrderDetailID INT PRIMARY KEY IDENTITY(1,1),
    OrderID INT NOT NULL,
    ProductID INT NOT NULL,
    Quantity INT NOT NULL CHECK (Quantity > 0),
    UnitPrice DECIMAL(10, 2) NOT NULL,
    Discount DECIMAL(5, 2) DEFAULT 0 CHECK (Discount >= 0 AND Discount <= 100),
    CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
    CONSTRAINT FK_OrderDetails_Products FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

CREATE TABLE InventoryLogs (
    LogID INT PRIMARY KEY IDENTITY(1,1),
    ProductID INT NOT NULL,
    ChangeDate DATETIME NOT NULL DEFAULT GETDATE(),
    QuantityChange INT NOT NULL,
    PreviousStock INT NOT NULL,
    NewStock INT NOT NULL,
    ChangeType NVARCHAR(20) NOT NULL CHECK (ChangeType IN ('Order', 'Replenishment', 'Adjustment', 'Initial')),
    ReferenceID INT,  -- Can be OrderID or other reference
    CONSTRAINT FK_InventoryLogs_Products FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

-- Create indexes for performance optimization
CREATE INDEX IX_Products_Category ON Products(Category);
CREATE INDEX IX_Products_StockLevel ON Products(StockQuantity, ReorderLevel);
CREATE INDEX IX_Orders_CustomerID ON Orders(CustomerID);
CREATE INDEX IX_OrderDetails_OrderID ON OrderDetails(OrderID);
CREATE INDEX IX_OrderDetails_ProductID ON OrderDetails(ProductID);
CREATE INDEX IX_InventoryLogs_ProductID ON InventoryLogs(ProductID);
CREATE INDEX IX_InventoryLogs_ChangeDate ON InventoryLogs(ChangeDate);

GO
-- Stored Procedures

-- Add a new product with initial inventory log
CREATE PROCEDURE sp_AddProduct
    @ProductName NVARCHAR(100),
    @Category NVARCHAR(50),
    @Price DECIMAL(10, 2),
    @StockQuantity INT,
    @ReorderLevel INT
AS
BEGIN
    BEGIN TRANSACTION;
    
    DECLARE @ProductID INT;
    
    INSERT INTO Products (ProductName, Category, Price, StockQuantity, ReorderLevel)
    VALUES (@ProductName, @Category, @Price, @StockQuantity, @ReorderLevel);
    
    SET @ProductID = SCOPE_IDENTITY();
    
    -- Log initial inventory
    IF @StockQuantity > 0
    BEGIN
        INSERT INTO InventoryLogs (ProductID, QuantityChange, PreviousStock, NewStock, ChangeType)
        VALUES (@ProductID, @StockQuantity, 0, @StockQuantity, 'Initial');
    END
    
    COMMIT TRANSACTION;
    
    SELECT @ProductID AS NewProductID;
END;
GO

-- Create a new order and process inventory changes
CREATE PROCEDURE sp_CreateOrder
    @CustomerID INT,
    @OrderItems OrderItemsTableType READONLY -- Custom table type for order items
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    
    DECLARE @OrderID INT;
    DECLARE @TotalAmount DECIMAL(12, 2) = 0;
    DECLARE @Error INT = 0;
    
    -- Create the order
    INSERT INTO Orders (CustomerID, OrderDate, TotalAmount)
    VALUES (@CustomerID, GETDATE(), 0);
    
    SET @OrderID = SCOPE_IDENTITY();
    
    -- Process each order item
    DECLARE @ProductID INT, @Quantity INT, @UnitPrice DECIMAL(10, 2), @CurrentStock INT, @Discount DECIMAL(5, 2);
    
    DECLARE ItemCursor CURSOR FOR
    SELECT ProductID, Quantity FROM @OrderItems;
    
    OPEN ItemCursor;
    FETCH NEXT FROM ItemCursor INTO @ProductID, @Quantity;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Get current product info
        SELECT @UnitPrice = Price, @CurrentStock = StockQuantity
        FROM Products
        WHERE ProductID = @ProductID;
        
        -- Check if we have enough stock
        IF @CurrentStock < @Quantity
        BEGIN
            SET @Error = 1;
            BREAK;
        END
        
        -- Calculate discount based on quantity
        SET @Discount = 
            CASE 
                WHEN @Quantity >= 100 THEN 25.0
                WHEN @Quantity >= 50 THEN 15.0
                WHEN @Quantity >= 20 THEN 10.0
                WHEN @Quantity >= 10 THEN 5.0
                ELSE 0.0
            END;
        
        -- Add order detail
        INSERT INTO OrderDetails (OrderID, ProductID, Quantity, UnitPrice, Discount)
        VALUES (@OrderID, @ProductID, @Quantity, @UnitPrice, @Discount);
        
        -- Update product stock
        UPDATE Products
        SET StockQuantity = StockQuantity - @Quantity
        WHERE ProductID = @ProductID;
        
        -- Add inventory log entry
        INSERT INTO InventoryLogs (ProductID, QuantityChange, PreviousStock, NewStock, ChangeType, ReferenceID)
        VALUES (@ProductID, -@Quantity, @CurrentStock, @CurrentStock - @Quantity, 'Order', @OrderID);
        
        -- Add to total amount (with discount applied)
        SET @TotalAmount = @TotalAmount + (@UnitPrice * @Quantity * (1 - @Discount/100));
        
        FETCH NEXT FROM ItemCursor INTO @ProductID, @Quantity;
    END
    
    CLOSE ItemCursor;
    DEALLOCATE ItemCursor;
    
    IF @Error = 1
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50000, 'Insufficient stock for one or more products in the order.', 1;
        RETURN;
    END
    
    -- Update order total
    UPDATE Orders
    SET TotalAmount = @TotalAmount
    WHERE OrderID = @OrderID;
    
    -- Update customer tier based on total spending
    UPDATE c
    SET CustomerTier = 
        CASE 
            WHEN TotalSpent >= 10000 THEN 'Platinum'
            WHEN TotalSpent >= 5000 THEN 'Gold'
            WHEN TotalSpent >= 1000 THEN 'Silver'
            ELSE 'Bronze'
        END
    FROM Customers c
    INNER JOIN (
        SELECT CustomerID, SUM(TotalAmount) AS TotalSpent
        FROM Orders
        WHERE CustomerID = @CustomerID
        GROUP BY CustomerID
    ) o ON c.CustomerID = o.CustomerID;
    
    COMMIT TRANSACTION;
    
    SELECT @OrderID AS NewOrderID, @TotalAmount AS OrderTotal;
END;
GO

-- Replenish product stock
CREATE PROCEDURE sp_ReplenishStock
    @ProductID INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Quantity <= 0
    BEGIN
        THROW 50000, 'Quantity must be greater than zero.', 1;
        RETURN;
    END
    
    DECLARE @CurrentStock INT;
    
    BEGIN TRANSACTION;
    
    -- Get current stock
    SELECT @CurrentStock = StockQuantity
    FROM Products
    WHERE ProductID = @ProductID;
    
    IF @@ROWCOUNT = 0
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50000, 'Product not found.', 1;
        RETURN;
    END
    
    -- Update stock
    UPDATE Products
    SET StockQuantity = StockQuantity + @Quantity
    WHERE ProductID = @ProductID;
    
    -- Log the replenishment
    INSERT INTO InventoryLogs (ProductID, QuantityChange, PreviousStock, NewStock, ChangeType)
    VALUES (@ProductID, @Quantity, @CurrentStock, @CurrentStock + @Quantity, 'Replenishment');
    
    COMMIT TRANSACTION;
END;
GO

-- Check products that need replenishment
CREATE PROCEDURE sp_CheckStockLevels
AS
BEGIN
    SELECT 
        ProductID,
        ProductName,
        Category,
        StockQuantity,
        ReorderLevel,
        (ReorderLevel - StockQuantity) AS QuantityToOrder
    FROM Products
    WHERE StockQuantity <= ReorderLevel
    ORDER BY (ReorderLevel - StockQuantity) DESC;
END;
GO

-- Custom table type for order items
CREATE TYPE OrderItemsTableType AS TABLE
(
    ProductID INT NOT NULL,
    Quantity INT NOT NULL
);
GO

-- Views for business insights

-- View for order summaries with customer info
CREATE VIEW vw_OrderSummary AS
SELECT 
    o.OrderID,
    c.CustomerID,
    c.CustomerName,
    o.OrderDate,
    o.TotalAmount,
    c.CustomerTier,
    COUNT(od.OrderDetailID) AS TotalItems,
    o.Status
FROM Orders o
JOIN Customers c ON o.CustomerID = c.CustomerID
JOIN OrderDetails od ON o.OrderID = od.OrderID
GROUP BY o.OrderID, c.CustomerID, c.CustomerName, o.OrderDate, o.TotalAmount, c.CustomerTier, o.Status;
GO

-- View for product stock status
CREATE VIEW vw_ProductStockStatus AS
SELECT 
    p.ProductID,
    p.ProductName,
    p.Category,
    p.Price,
    p.StockQuantity,
    p.ReorderLevel,
    CASE 
        WHEN p.StockQuantity <= p.ReorderLevel THEN 'Low Stock'
        WHEN p.StockQuantity <= p.ReorderLevel * 2 THEN 'Moderate Stock'
        ELSE 'Sufficient Stock'
    END AS StockStatus,
    CASE 
        WHEN p.StockQuantity <= p.ReorderLevel THEN 'Yes'
        ELSE 'No'
    END AS NeedsReplenishment
FROM Products p;
GO

-- View for customer spending summary
CREATE VIEW vw_CustomerSpendingSummary AS
SELECT 
    c.CustomerID,
    c.CustomerName,
    c.Email,
    c.CustomerTier,
    COUNT(DISTINCT o.OrderID) AS TotalOrders,
    SUM(o.TotalAmount) AS TotalSpent,
    AVG(o.TotalAmount) AS AverageOrderValue,
    MAX(o.OrderDate) AS LastOrderDate
FROM Customers c
LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID, c.CustomerName, c.Email, c.CustomerTier;
GO

-- View for inventory change history
CREATE VIEW vw_InventoryChangeHistory AS
SELECT 
    il.LogID,
    p.ProductID,
    p.ProductName,
    il.ChangeDate,
    il.QuantityChange,
    il.PreviousStock,
    il.NewStock,
    il.ChangeType,
    il.ReferenceID
FROM InventoryLogs il
JOIN Products p ON il.ProductID = p.ProductID;
GO