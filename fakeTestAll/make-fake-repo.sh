#!/usr/bin/env bash
# Builds the fake "Corner Bakery" app repo with two mocked pull requests. Nothing here is real:
# no remote, a made-up author, fixed dates (so the commit ids are the same on every run).
#
#   main ── pr-7-base ──(merge of PR #7)── pr-8-base
#              └─ feature/cancel-order (pr-7-head)      └─ feature/refund-on-cancel (pr-8-head)
#
# Usage: make-fake-repo.sh            writes ./repo next to this script (replacing it)
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$here/repo
case $repo in */fakeTestAll/repo) ;; *) echo "refusing to replace $repo" >&2; exit 1;; esac
rm -rf "$repo"; mkdir -p "$repo"; cd "$repo"

export GIT_AUTHOR_NAME="Mock Author" GIT_AUTHOR_EMAIL="mock@example.com"
export GIT_COMMITTER_NAME="Mock Author" GIT_COMMITTER_EMAIL="mock@example.com"
git init -q -b main
w() { mkdir -p "$(dirname "$1")"; cat > "$1"; }
commit() { git add -A; GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -c commit.gpgsign=false commit -q -m "$2"; }

J=src/main/java/bakery; T=src/test/java/bakery; DB=src/main/resources/db/migration

# ------------------------------------------------------------------ main: place, mark ready, pick up
w README.md <<'EOF'
# Corner Bakery

Order desk for a small bakery: place an order, mark it ready, hand it over.

A fake app for testing design maps. Nothing here is real.
EOF

w pom.xml <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>example</groupId>
  <artifactId>corner-bakery</artifactId>
  <version>0.3.0</version>
  <properties>
    <maven.compiler.release>21</maven.compiler.release>
  </properties>
</project>
EOF

w $J/api/OrderController.java <<'EOF'
package bakery.api;

import bakery.api.dto.OrderRequest;
import bakery.orders.Order;
import bakery.orders.OrderService;
import bakery.orders.command.MarkReady;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;

public class OrderController {

    private final OrderService orders;

    public OrderController(OrderService orders) {
        this.orders = orders;
    }

    // POST /orders
    public Order place(OrderRequest request) {
        return orders.handle(new PlaceOrder(request.customer(), request.items()));
    }

    // POST /orders/{id}/ready
    public Order ready(String orderId) {
        return orders.handle(new MarkReady(orderId));
    }

    // POST /orders/{id}/pick-up
    public Order pickUp(String orderId) {
        return orders.handle(new PickUp(orderId));
    }

    // GET /orders/{id}
    public Order find(String orderId) {
        return orders.find(orderId);
    }
}
EOF

w $J/api/dto/OrderRequest.java <<'EOF'
package bakery.api.dto;

import java.util.List;

public record OrderRequest(String customer, List<String> items) {
}
EOF

w $J/orders/Order.java <<'EOF'
package bakery.orders;

import java.time.Instant;
import java.util.List;

public record Order(
        String id,
        String customer,
        List<String> items,
        int totalCents,
        OrderStatus status,
        Instant placedAt) {

    public Order withStatus(OrderStatus next) {
        return new Order(id, customer, items, totalCents, next, placedAt);
    }
}
EOF

w $J/orders/OrderStatus.java <<'EOF'
package bakery.orders;

public enum OrderStatus {
    PLACED,
    READY,
    PICKED_UP
}
EOF

w $J/orders/OrderNotFound.java <<'EOF'
package bakery.orders;

public class OrderNotFound extends RuntimeException {

    public OrderNotFound(String orderId) {
        super("no order " + orderId);
    }
}
EOF

w $J/orders/IllegalTransition.java <<'EOF'
package bakery.orders;

public class IllegalTransition extends RuntimeException {

    public IllegalTransition(String orderId, OrderStatus from, OrderStatus to) {
        super("order " + orderId + " cannot go from " + from + " to " + to);
    }
}
EOF

w $J/orders/command/OrderCommand.java <<'EOF'
package bakery.orders.command;

public sealed interface OrderCommand permits PlaceOrder, MarkReady, PickUp {
}
EOF

w $J/orders/command/PlaceOrder.java <<'EOF'
package bakery.orders.command;

import java.util.List;

public record PlaceOrder(String customer, List<String> items) implements OrderCommand {
}
EOF

w $J/orders/command/MarkReady.java <<'EOF'
package bakery.orders.command;

public record MarkReady(String orderId) implements OrderCommand {
}
EOF

w $J/orders/command/PickUp.java <<'EOF'
package bakery.orders.command;

public record PickUp(String orderId) implements OrderCommand {
}
EOF

w $J/orders/OrderService.java <<'EOF'
package bakery.orders;

import bakery.orders.command.MarkReady;
import bakery.orders.command.OrderCommand;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;
import bakery.pricing.PriceList;
import bakery.storage.OrderRepository;
import java.time.Clock;
import java.util.UUID;

public class OrderService {

    private final OrderRepository repository;
    private final PriceList prices;
    private final Clock clock;

    public OrderService(OrderRepository repository, PriceList prices, Clock clock) {
        this.repository = repository;
        this.prices = prices;
        this.clock = clock;
    }

    public Order handle(OrderCommand command) {
        return switch (command) {
            case PlaceOrder place -> place(place);
            case MarkReady ready -> move(ready.orderId(), OrderStatus.PLACED, OrderStatus.READY);
            case PickUp pickUp -> move(pickUp.orderId(), OrderStatus.READY, OrderStatus.PICKED_UP);
        };
    }

    public Order find(String orderId) {
        return repository.findById(orderId)
                .orElseThrow(() -> new OrderNotFound(orderId));
    }

    private Order place(PlaceOrder command) {
        int totalCents = prices.totalCents(command.items());
        String id = "B" + UUID.randomUUID().toString().substring(0, 6);
        Order order = new Order(id, command.customer(), command.items(), totalCents, OrderStatus.PLACED, clock.instant());
        return repository.save(order);
    }

    private Order move(String orderId, OrderStatus from, OrderStatus to) {
        Order order = find(orderId);
        if (order.status() != from) {
            throw new IllegalTransition(orderId, order.status(), to);
        }
        return repository.save(order.withStatus(to));
    }
}
EOF

w $J/pricing/PriceList.java <<'EOF'
package bakery.pricing;

import java.util.List;
import java.util.Map;

public class PriceList {

    private final Map<String, Integer> centsByItem;

    public PriceList(Map<String, Integer> centsByItem) {
        this.centsByItem = Map.copyOf(centsByItem);
    }

    public int totalCents(List<String> items) {
        return items.stream()
                .mapToInt(item -> centsByItem.getOrDefault(item, 0))
                .sum();
    }
}
EOF

w $J/storage/OrderRepository.java <<'EOF'
package bakery.storage;

import bakery.orders.Order;
import java.util.Optional;

public interface OrderRepository {

    Order save(Order order);

    Optional<Order> findById(String orderId);
}
EOF

w $J/storage/Sql.java <<'EOF'
package bakery.storage;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Optional;
import javax.sql.DataSource;

// the two JDBC calls the repositories need
class Sql {

    interface RowMapper<T> {
        T map(ResultSet row) throws SQLException;
    }

    private final DataSource dataSource;

    Sql(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    void update(String statement, Object... values) {
        try (Connection connection = dataSource.getConnection();
             PreparedStatement prepared = bind(connection.prepareStatement(statement), values)) {
            prepared.executeUpdate();
        } catch (SQLException e) {
            throw new IllegalStateException(e);
        }
    }

    <T> Optional<T> queryOne(String query, RowMapper<T> mapper, Object... values) {
        try (Connection connection = dataSource.getConnection();
             PreparedStatement prepared = bind(connection.prepareStatement(query), values);
             ResultSet row = prepared.executeQuery()) {
            return row.next() ? Optional.of(mapper.map(row)) : Optional.empty();
        } catch (SQLException e) {
            throw new IllegalStateException(e);
        }
    }

    private static PreparedStatement bind(PreparedStatement prepared, Object... values) throws SQLException {
        for (int i = 0; i < values.length; i++) {
            prepared.setObject(i + 1, values[i]);
        }
        return prepared;
    }
}
EOF

w $J/storage/JdbcOrderRepository.java <<'EOF'
package bakery.storage;

import bakery.orders.Order;
import bakery.orders.OrderStatus;
import java.sql.Timestamp;
import java.util.List;
import java.util.Optional;
import javax.sql.DataSource;

public class JdbcOrderRepository implements OrderRepository {

    private static final String UPSERT = """
            INSERT INTO orders (id, customer, items, total_cents, status, placed_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status
            """;

    private static final String BY_ID = "SELECT * FROM orders WHERE id = ?";

    private final Sql sql;

    public JdbcOrderRepository(DataSource dataSource) {
        this.sql = new Sql(dataSource);
    }

    @Override
    public Order save(Order order) {
        sql.update(UPSERT,
                order.id(),
                order.customer(),
                String.join(",", order.items()),
                order.totalCents(),
                order.status().name(),
                Timestamp.from(order.placedAt()));
        return order;
    }

    @Override
    public Optional<Order> findById(String orderId) {
        return sql.queryOne(BY_ID, row -> new Order(
                row.getString("id"),
                row.getString("customer"),
                List.of(row.getString("items").split(",")),
                row.getInt("total_cents"),
                OrderStatus.valueOf(row.getString("status")),
                row.getTimestamp("placed_at").toInstant()), orderId);
    }
}
EOF

w $DB/V1__orders.sql <<'EOF'
CREATE TABLE orders (
    id          TEXT PRIMARY KEY,
    customer    TEXT NOT NULL,
    items       TEXT NOT NULL,
    total_cents INTEGER NOT NULL,
    status      TEXT NOT NULL,
    placed_at   TIMESTAMP NOT NULL
);
EOF

w $T/support/InMemoryOrderRepository.java <<'EOF'
package bakery.support;

import bakery.orders.Order;
import bakery.storage.OrderRepository;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

public class InMemoryOrderRepository implements OrderRepository {

    private final Map<String, Order> ordersById = new HashMap<>();

    @Override
    public Order save(Order order) {
        ordersById.put(order.id(), order);
        return order;
    }

    @Override
    public Optional<Order> findById(String orderId) {
        return Optional.ofNullable(ordersById.get(orderId));
    }
}
EOF

w $T/orders/OrderServiceTest.java <<'EOF'
package bakery.orders;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import bakery.orders.command.MarkReady;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;
import bakery.pricing.PriceList;
import bakery.support.InMemoryOrderRepository;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class OrderServiceTest {

    private final OrderService orders = new OrderService(
            new InMemoryOrderRepository(),
            new PriceList(Map.of("croissant", 350, "baguette", 420)),
            Clock.systemUTC());

    @Test
    void placesAnOrderWithItsTotal() {
        Order order = orders.handle(new PlaceOrder("Ana", List.of("croissant", "baguette")));

        assertEquals(OrderStatus.PLACED, order.status());
        assertEquals(770, order.totalCents());
    }

    @Test
    void readyThenPickedUp() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));

        orders.handle(new MarkReady(placed.id()));
        Order pickedUp = orders.handle(new PickUp(placed.id()));

        assertEquals(OrderStatus.PICKED_UP, pickedUp.status());
    }

    @Test
    void cannotPickUpBeforeReady() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));

        assertThrows(IllegalTransition.class, () -> orders.handle(new PickUp(placed.id())));
    }
}
EOF

w $T/pricing/PriceListTest.java <<'EOF'
package bakery.pricing;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class PriceListTest {

    @Test
    void sumsKnownItemsAndSkipsUnknownOnes() {
        PriceList prices = new PriceList(Map.of("croissant", 350));

        assertEquals(700, prices.totalCents(List.of("croissant", "croissant", "mystery")));
    }
}
EOF

commit "2026-11-02T09:00:00-06:00" "Order desk: place, mark ready, pick up"
git tag pr-7-base

# ------------------------------------------------------------------ PR #7: cancel an order
git checkout -q -b feature/cancel-order

w $J/orders/CancelReason.java <<'EOF'
package bakery.orders;

public enum CancelReason {
    CUSTOMER_REQUEST,
    OUT_OF_STOCK,
    SHOP_CLOSED
}
EOF

w $J/orders/command/CancelOrder.java <<'EOF'
package bakery.orders.command;

import bakery.orders.CancelReason;

public record CancelOrder(String orderId, CancelReason reason) implements OrderCommand {
}
EOF

w $J/orders/command/OrderCommand.java <<'EOF'
package bakery.orders.command;

public sealed interface OrderCommand permits PlaceOrder, MarkReady, PickUp, CancelOrder {
}
EOF

w $J/orders/OrderStatus.java <<'EOF'
package bakery.orders;

public enum OrderStatus {
    PLACED,
    READY,
    PICKED_UP,
    CANCELLED
}
EOF

w $J/orders/Order.java <<'EOF'
package bakery.orders;

import java.time.Instant;
import java.util.List;

public record Order(
        String id,
        String customer,
        List<String> items,
        int totalCents,
        OrderStatus status,
        Instant placedAt,
        CancelReason cancelReason,
        Instant cancelledAt) {

    public Order withStatus(OrderStatus next) {
        return new Order(id, customer, items, totalCents, next, placedAt, cancelReason, cancelledAt);
    }

    // a cancelled order keeps why and when
    public Order cancelled(CancelReason reason, Instant at) {
        return new Order(id, customer, items, totalCents, OrderStatus.CANCELLED, placedAt, reason, at);
    }
}
EOF

w $J/orders/OrderService.java <<'EOF'
package bakery.orders;

import bakery.orders.command.CancelOrder;
import bakery.orders.command.MarkReady;
import bakery.orders.command.OrderCommand;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;
import bakery.pricing.PriceList;
import bakery.storage.OrderRepository;
import java.time.Clock;
import java.util.UUID;

public class OrderService {

    private final OrderRepository repository;
    private final PriceList prices;
    private final Clock clock;

    public OrderService(OrderRepository repository, PriceList prices, Clock clock) {
        this.repository = repository;
        this.prices = prices;
        this.clock = clock;
    }

    public Order handle(OrderCommand command) {
        return switch (command) {
            case PlaceOrder place -> place(place);
            case MarkReady ready -> move(ready.orderId(), OrderStatus.PLACED, OrderStatus.READY);
            case PickUp pickUp -> move(pickUp.orderId(), OrderStatus.READY, OrderStatus.PICKED_UP);
            case CancelOrder cancel -> cancel(cancel);
        };
    }

    public Order find(String orderId) {
        return repository.findById(orderId)
                .orElseThrow(() -> new OrderNotFound(orderId));
    }

    private Order place(PlaceOrder command) {
        int totalCents = prices.totalCents(command.items());
        String id = "B" + UUID.randomUUID().toString().substring(0, 6);
        Order order = new Order(id, command.customer(), command.items(), totalCents, OrderStatus.PLACED, clock.instant(), null, null);
        return repository.save(order);
    }

    private Order move(String orderId, OrderStatus from, OrderStatus to) {
        Order order = find(orderId);
        if (order.status() != from) {
            throw new IllegalTransition(orderId, order.status(), to);
        }
        return repository.save(order.withStatus(to));
    }

    private Order cancel(CancelOrder command) {
        Order order = find(command.orderId());

        // only an order still in the shop can be cancelled
        if (order.status() == OrderStatus.PICKED_UP || order.status() == OrderStatus.CANCELLED) {
            throw new IllegalTransition(order.id(), order.status(), OrderStatus.CANCELLED);
        }

        Order cancelled = order.cancelled(command.reason(), clock.instant());
        return repository.save(cancelled);
    }
}
EOF

w $J/api/dto/CancelRequest.java <<'EOF'
package bakery.api.dto;

public record CancelRequest(String reason) {
}
EOF

w $J/api/OrderController.java <<'EOF'
package bakery.api;

import bakery.api.dto.CancelRequest;
import bakery.api.dto.OrderRequest;
import bakery.orders.CancelReason;
import bakery.orders.Order;
import bakery.orders.OrderService;
import bakery.orders.command.CancelOrder;
import bakery.orders.command.MarkReady;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;

public class OrderController {

    private final OrderService orders;

    public OrderController(OrderService orders) {
        this.orders = orders;
    }

    // POST /orders
    public Order place(OrderRequest request) {
        return orders.handle(new PlaceOrder(request.customer(), request.items()));
    }

    // POST /orders/{id}/ready
    public Order ready(String orderId) {
        return orders.handle(new MarkReady(orderId));
    }

    // POST /orders/{id}/pick-up
    public Order pickUp(String orderId) {
        return orders.handle(new PickUp(orderId));
    }

    // DELETE /orders/{id}
    public Order cancel(String orderId, CancelRequest request) {
        CancelReason reason = CancelReason.valueOf(request.reason());
        return orders.handle(new CancelOrder(orderId, reason));
    }

    // GET /orders/{id}
    public Order find(String orderId) {
        return orders.find(orderId);
    }
}
EOF

w $J/storage/JdbcOrderRepository.java <<'EOF'
package bakery.storage;

import bakery.orders.CancelReason;
import bakery.orders.Order;
import bakery.orders.OrderStatus;
import java.sql.Timestamp;
import java.util.List;
import java.util.Optional;
import javax.sql.DataSource;

public class JdbcOrderRepository implements OrderRepository {

    private static final String UPSERT = """
            INSERT INTO orders (id, customer, items, total_cents, status, placed_at, cancel_reason, cancelled_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                status = EXCLUDED.status,
                cancel_reason = EXCLUDED.cancel_reason,
                cancelled_at = EXCLUDED.cancelled_at
            """;

    private static final String BY_ID = "SELECT * FROM orders WHERE id = ?";

    private final Sql sql;

    public JdbcOrderRepository(DataSource dataSource) {
        this.sql = new Sql(dataSource);
    }

    @Override
    public Order save(Order order) {
        sql.update(UPSERT,
                order.id(),
                order.customer(),
                String.join(",", order.items()),
                order.totalCents(),
                order.status().name(),
                Timestamp.from(order.placedAt()),
                order.cancelReason() == null ? null : order.cancelReason().name(),
                order.cancelledAt() == null ? null : Timestamp.from(order.cancelledAt()));
        return order;
    }

    @Override
    public Optional<Order> findById(String orderId) {
        return sql.queryOne(BY_ID, row -> new Order(
                row.getString("id"),
                row.getString("customer"),
                List.of(row.getString("items").split(",")),
                row.getInt("total_cents"),
                OrderStatus.valueOf(row.getString("status")),
                row.getTimestamp("placed_at").toInstant(),
                row.getString("cancel_reason") == null ? null : CancelReason.valueOf(row.getString("cancel_reason")),
                row.getTimestamp("cancelled_at") == null ? null : row.getTimestamp("cancelled_at").toInstant()), orderId);
    }
}
EOF

w $DB/V2__order_cancellation.sql <<'EOF'
ALTER TABLE orders
    ADD COLUMN cancel_reason TEXT NULL,
    ADD COLUMN cancelled_at  TIMESTAMP NULL;
EOF

w $T/orders/OrderServiceCancelTest.java <<'EOF'
package bakery.orders;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import bakery.orders.command.CancelOrder;
import bakery.orders.command.MarkReady;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;
import bakery.pricing.PriceList;
import bakery.support.InMemoryOrderRepository;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class OrderServiceCancelTest {

    private final OrderService orders = new OrderService(
            new InMemoryOrderRepository(),
            new PriceList(Map.of("croissant", 350)),
            Clock.systemUTC());

    @Test
    void cancelsAPlacedOrder() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));

        Order cancelled = orders.handle(new CancelOrder(placed.id(), CancelReason.CUSTOMER_REQUEST));

        assertEquals(OrderStatus.CANCELLED, cancelled.status());
        assertEquals(CancelReason.CUSTOMER_REQUEST, cancelled.cancelReason());
        assertNotNull(cancelled.cancelledAt());
    }

    @Test
    void cancelsAReadyOrder() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));
        orders.handle(new MarkReady(placed.id()));

        Order cancelled = orders.handle(new CancelOrder(placed.id(), CancelReason.SHOP_CLOSED));

        assertEquals(OrderStatus.CANCELLED, cancelled.status());
    }

    @Test
    void cannotCancelAfterPickUp() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));
        orders.handle(new MarkReady(placed.id()));
        orders.handle(new PickUp(placed.id()));

        assertThrows(IllegalTransition.class,
                () -> orders.handle(new CancelOrder(placed.id(), CancelReason.CUSTOMER_REQUEST)));
    }

    @Test
    void cannotCancelTwice() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));
        orders.handle(new CancelOrder(placed.id(), CancelReason.OUT_OF_STOCK));

        assertThrows(IllegalTransition.class,
                () -> orders.handle(new CancelOrder(placed.id(), CancelReason.OUT_OF_STOCK)));
    }
}
EOF

w $T/api/OrderControllerIT.java <<'EOF'
package bakery.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import bakery.api.dto.CancelRequest;
import bakery.api.dto.OrderRequest;
import bakery.orders.Order;
import bakery.orders.OrderService;
import bakery.orders.OrderStatus;
import bakery.pricing.PriceList;
import bakery.support.InMemoryOrderRepository;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class OrderControllerIT {

    private final OrderController controller = new OrderController(new OrderService(
            new InMemoryOrderRepository(),
            new PriceList(Map.of("croissant", 350)),
            Clock.systemUTC()));

    @Test
    void deleteCancelsTheOrder() {
        Order placed = controller.place(new OrderRequest("Ana", List.of("croissant")));

        Order cancelled = controller.cancel(placed.id(), new CancelRequest("CUSTOMER_REQUEST"));

        assertEquals(OrderStatus.CANCELLED, cancelled.status());
    }

    @Test
    void unknownReasonIsRejected() {
        Order placed = controller.place(new OrderRequest("Ana", List.of("croissant")));

        assertThrows(IllegalArgumentException.class,
                () -> controller.cancel(placed.id(), new CancelRequest("CHANGED_MY_MIND")));
    }
}
EOF

w $T/orders/OrderServiceTest.java <<'EOF'
package bakery.orders;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import bakery.orders.command.MarkReady;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;
import bakery.pricing.PriceList;
import bakery.support.InMemoryOrderRepository;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class OrderServiceTest {

    private final OrderService orders = new OrderService(
            new InMemoryOrderRepository(),
            new PriceList(Map.of("croissant", 350, "baguette", 420)),
            Clock.systemUTC());

    @Test
    void placesAnOrderWithItsTotal() {
        Order order = orders.handle(new PlaceOrder("Ana", List.of("croissant", "baguette")));

        assertEquals(OrderStatus.PLACED, order.status());
        assertEquals(770, order.totalCents());
        assertNull(order.cancelReason());
    }

    @Test
    void readyThenPickedUp() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));

        orders.handle(new MarkReady(placed.id()));
        Order pickedUp = orders.handle(new PickUp(placed.id()));

        assertEquals(OrderStatus.PICKED_UP, pickedUp.status());
    }

    @Test
    void cannotPickUpBeforeReady() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));

        assertThrows(IllegalTransition.class, () -> orders.handle(new PickUp(placed.id())));
    }
}
EOF

w docs/orders.md <<'EOF'
# Orders

| Call | Does |
|---|---|
| POST /orders | place an order |
| POST /orders/{id}/ready | mark it ready |
| POST /orders/{id}/pick-up | hand it over |
| DELETE /orders/{id} | cancel it, with a reason |

An order can be cancelled until it is picked up.
EOF

w README.md <<'EOF'
# Corner Bakery

Order desk for a small bakery: place an order, mark it ready, hand it over, or cancel it.

The calls are listed in [docs/orders.md](docs/orders.md).

A fake app for testing design maps. Nothing here is real.
EOF

commit "2026-11-09T14:20:00-06:00" "Cancel an order, with a reason"
git tag pr-7-head
git update-ref refs/pull/7/head pr-7-head

git checkout -q main
GIT_AUTHOR_DATE="2026-11-10T10:05:00-06:00" GIT_COMMITTER_DATE="2026-11-10T10:05:00-06:00" \
  git -c commit.gpgsign=false merge -q --no-ff -m "Merge pull request #7 from example/feature/cancel-order" feature/cancel-order
git tag pr-8-base

# ------------------------------------------------------------------ PR #8: refund on cancel
git checkout -q -b feature/refund-on-cancel

w $J/pricing/RefundPolicy.java <<'EOF'
package bakery.pricing;

public sealed interface RefundPolicy permits FullRefund, HalfRefund, NoRefund {

    int refundCents(int totalCents);
}
EOF

w $J/pricing/FullRefund.java <<'EOF'
package bakery.pricing;

public record FullRefund() implements RefundPolicy {

    @Override
    public int refundCents(int totalCents) {
        return totalCents;
    }
}
EOF

w $J/pricing/HalfRefund.java <<'EOF'
package bakery.pricing;

public record HalfRefund() implements RefundPolicy {

    @Override
    public int refundCents(int totalCents) {
        return totalCents / 2;
    }
}
EOF

w $J/pricing/NoRefund.java <<'EOF'
package bakery.pricing;

public record NoRefund() implements RefundPolicy {

    @Override
    public int refundCents(int totalCents) {
        return 0;
    }
}
EOF

w $J/pricing/RefundCalculator.java <<'EOF'
package bakery.pricing;

import bakery.orders.Order;
import bakery.orders.OrderStatus;

public class RefundCalculator {

    // nothing baked yet: all of it back. Already baked: half. Otherwise nothing.
    public RefundPolicy policyFor(OrderStatus statusBeforeCancel) {
        return switch (statusBeforeCancel) {
            case PLACED -> new FullRefund();
            case READY -> new HalfRefund();
            case PICKED_UP, CANCELLED -> new NoRefund();
        };
    }

    public int refundCents(Order order) {
        RefundPolicy policy = policyFor(order.status());
        return policy.refundCents(order.totalCents());
    }
}
EOF

w $J/payments/Refund.java <<'EOF'
package bakery.payments;

import java.time.Instant;

public record Refund(String id, String orderId, int cents, Instant issuedAt) {
}
EOF

w $J/payments/PaymentGateway.java <<'EOF'
package bakery.payments;

public interface PaymentGateway {

    Refund refund(String orderId, int cents);
}
EOF

w $J/orders/Order.java <<'EOF'
package bakery.orders;

import java.time.Instant;
import java.util.List;

public record Order(
        String id,
        String customer,
        List<String> items,
        int totalCents,
        OrderStatus status,
        Instant placedAt,
        CancelReason cancelReason,
        Instant cancelledAt,
        int refundCents) {

    public Order withStatus(OrderStatus next) {
        return new Order(id, customer, items, totalCents, next, placedAt, cancelReason, cancelledAt, refundCents);
    }

    // a cancelled order keeps why, when and how much went back
    public Order cancelled(CancelReason reason, Instant at, int refundedCents) {
        return new Order(id, customer, items, totalCents, OrderStatus.CANCELLED, placedAt, reason, at, refundedCents);
    }
}
EOF

w $J/orders/OrderService.java <<'EOF'
package bakery.orders;

import bakery.orders.command.CancelOrder;
import bakery.orders.command.MarkReady;
import bakery.orders.command.OrderCommand;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;
import bakery.payments.PaymentGateway;
import bakery.pricing.PriceList;
import bakery.pricing.RefundCalculator;
import bakery.storage.OrderRepository;
import java.time.Clock;
import java.util.UUID;

public class OrderService {

    private final OrderRepository repository;
    private final PriceList prices;
    private final RefundCalculator refunds;
    private final PaymentGateway payments;
    private final Clock clock;

    public OrderService(OrderRepository repository, PriceList prices, RefundCalculator refunds,
                        PaymentGateway payments, Clock clock) {
        this.repository = repository;
        this.prices = prices;
        this.refunds = refunds;
        this.payments = payments;
        this.clock = clock;
    }

    public Order handle(OrderCommand command) {
        return switch (command) {
            case PlaceOrder place -> place(place);
            case MarkReady ready -> move(ready.orderId(), OrderStatus.PLACED, OrderStatus.READY);
            case PickUp pickUp -> move(pickUp.orderId(), OrderStatus.READY, OrderStatus.PICKED_UP);
            case CancelOrder cancel -> cancel(cancel);
        };
    }

    public Order find(String orderId) {
        return repository.findById(orderId)
                .orElseThrow(() -> new OrderNotFound(orderId));
    }

    private Order place(PlaceOrder command) {
        int totalCents = prices.totalCents(command.items());
        String id = "B" + UUID.randomUUID().toString().substring(0, 6);
        Order order = new Order(id, command.customer(), command.items(), totalCents, OrderStatus.PLACED, clock.instant(), null, null, 0);
        return repository.save(order);
    }

    private Order move(String orderId, OrderStatus from, OrderStatus to) {
        Order order = find(orderId);
        if (order.status() != from) {
            throw new IllegalTransition(orderId, order.status(), to);
        }
        return repository.save(order.withStatus(to));
    }

    private Order cancel(CancelOrder command) {
        Order order = find(command.orderId());

        // only an order still in the shop can be cancelled
        if (order.status() == OrderStatus.PICKED_UP || order.status() == OrderStatus.CANCELLED) {
            throw new IllegalTransition(order.id(), order.status(), OrderStatus.CANCELLED);
        }

        // how much goes back depends on how far the order got
        int refundCents = refunds.refundCents(order);
        if (refundCents > 0) {
            payments.refund(order.id(), refundCents);
        }

        Order cancelled = order.cancelled(command.reason(), clock.instant(), refundCents);
        return repository.save(cancelled);
    }
}
EOF

w $J/storage/JdbcOrderRepository.java <<'EOF'
package bakery.storage;

import bakery.orders.CancelReason;
import bakery.orders.Order;
import bakery.orders.OrderStatus;
import java.sql.Timestamp;
import java.util.List;
import java.util.Optional;
import javax.sql.DataSource;

public class JdbcOrderRepository implements OrderRepository {

    private static final String UPSERT = """
            INSERT INTO orders (id, customer, items, total_cents, status, placed_at, cancel_reason, cancelled_at, refund_cents)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                status = EXCLUDED.status,
                cancel_reason = EXCLUDED.cancel_reason,
                cancelled_at = EXCLUDED.cancelled_at,
                refund_cents = EXCLUDED.refund_cents
            """;

    private static final String BY_ID = "SELECT * FROM orders WHERE id = ?";

    private final Sql sql;

    public JdbcOrderRepository(DataSource dataSource) {
        this.sql = new Sql(dataSource);
    }

    @Override
    public Order save(Order order) {
        sql.update(UPSERT,
                order.id(),
                order.customer(),
                String.join(",", order.items()),
                order.totalCents(),
                order.status().name(),
                Timestamp.from(order.placedAt()),
                order.cancelReason() == null ? null : order.cancelReason().name(),
                order.cancelledAt() == null ? null : Timestamp.from(order.cancelledAt()),
                order.refundCents());
        return order;
    }

    @Override
    public Optional<Order> findById(String orderId) {
        return sql.queryOne(BY_ID, row -> new Order(
                row.getString("id"),
                row.getString("customer"),
                List.of(row.getString("items").split(",")),
                row.getInt("total_cents"),
                OrderStatus.valueOf(row.getString("status")),
                row.getTimestamp("placed_at").toInstant(),
                row.getString("cancel_reason") == null ? null : CancelReason.valueOf(row.getString("cancel_reason")),
                row.getTimestamp("cancelled_at") == null ? null : row.getTimestamp("cancelled_at").toInstant(),
                row.getInt("refund_cents")), orderId);
    }
}
EOF

w $DB/V3__order_refunds.sql <<'EOF'
ALTER TABLE orders
    ADD COLUMN refund_cents INTEGER NOT NULL DEFAULT 0;

CREATE TABLE refunds (
    id        TEXT PRIMARY KEY,
    order_id  TEXT NOT NULL REFERENCES orders (id),
    cents     INTEGER NOT NULL,
    issued_at TIMESTAMP NOT NULL
);
EOF

w $T/support/RecordingPaymentGateway.java <<'EOF'
package bakery.support;

import bakery.payments.PaymentGateway;
import bakery.payments.Refund;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

public class RecordingPaymentGateway implements PaymentGateway {

    public final List<Refund> refunds = new ArrayList<>();

    @Override
    public Refund refund(String orderId, int cents) {
        Refund refund = new Refund("R" + (refunds.size() + 1), orderId, cents, Instant.now());
        refunds.add(refund);
        return refund;
    }
}
EOF

w $T/pricing/RefundCalculatorTest.java <<'EOF'
package bakery.pricing;

import static org.junit.jupiter.api.Assertions.assertEquals;

import bakery.orders.OrderStatus;
import org.junit.jupiter.api.Test;

class RefundCalculatorTest {

    private final RefundCalculator refunds = new RefundCalculator();

    @Test
    void placedGetsEverythingBack() {
        assertEquals(700, refunds.policyFor(OrderStatus.PLACED).refundCents(700));
    }

    @Test
    void readyGetsHalfBack() {
        assertEquals(350, refunds.policyFor(OrderStatus.READY).refundCents(700));
    }

    @Test
    void pickedUpGetsNothingBack() {
        assertEquals(0, refunds.policyFor(OrderStatus.PICKED_UP).refundCents(700));
    }
}
EOF

w $T/orders/OrderServiceCancelTest.java <<'EOF'
package bakery.orders;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import bakery.orders.command.CancelOrder;
import bakery.orders.command.MarkReady;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;
import bakery.pricing.PriceList;
import bakery.pricing.RefundCalculator;
import bakery.support.InMemoryOrderRepository;
import bakery.support.RecordingPaymentGateway;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class OrderServiceCancelTest {

    private final RecordingPaymentGateway payments = new RecordingPaymentGateway();

    private final OrderService orders = new OrderService(
            new InMemoryOrderRepository(),
            new PriceList(Map.of("croissant", 350)),
            new RefundCalculator(),
            payments,
            Clock.systemUTC());

    @Test
    void cancelsAPlacedOrderWithAFullRefund() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant", "croissant")));

        Order cancelled = orders.handle(new CancelOrder(placed.id(), CancelReason.CUSTOMER_REQUEST));

        assertEquals(OrderStatus.CANCELLED, cancelled.status());
        assertEquals(CancelReason.CUSTOMER_REQUEST, cancelled.cancelReason());
        assertNotNull(cancelled.cancelledAt());
        assertEquals(700, cancelled.refundCents());
        assertEquals(700, payments.refunds.get(0).cents());
    }

    @Test
    void cancelsAReadyOrderWithHalfBack() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant", "croissant")));
        orders.handle(new MarkReady(placed.id()));

        Order cancelled = orders.handle(new CancelOrder(placed.id(), CancelReason.SHOP_CLOSED));

        assertEquals(350, cancelled.refundCents());
    }

    @Test
    void cannotCancelAfterPickUp() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));
        orders.handle(new MarkReady(placed.id()));
        orders.handle(new PickUp(placed.id()));

        assertThrows(IllegalTransition.class,
                () -> orders.handle(new CancelOrder(placed.id(), CancelReason.CUSTOMER_REQUEST)));
        assertEquals(0, payments.refunds.size());
    }

    @Test
    void cannotCancelTwice() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));
        orders.handle(new CancelOrder(placed.id(), CancelReason.OUT_OF_STOCK));

        assertThrows(IllegalTransition.class,
                () -> orders.handle(new CancelOrder(placed.id(), CancelReason.OUT_OF_STOCK)));
        assertEquals(1, payments.refunds.size());
    }
}
EOF

w $T/orders/OrderServiceTest.java <<'EOF'
package bakery.orders;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import bakery.orders.command.MarkReady;
import bakery.orders.command.PickUp;
import bakery.orders.command.PlaceOrder;
import bakery.pricing.PriceList;
import bakery.pricing.RefundCalculator;
import bakery.support.InMemoryOrderRepository;
import bakery.support.RecordingPaymentGateway;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class OrderServiceTest {

    private final OrderService orders = new OrderService(
            new InMemoryOrderRepository(),
            new PriceList(Map.of("croissant", 350, "baguette", 420)),
            new RefundCalculator(),
            new RecordingPaymentGateway(),
            Clock.systemUTC());

    @Test
    void placesAnOrderWithItsTotal() {
        Order order = orders.handle(new PlaceOrder("Ana", List.of("croissant", "baguette")));

        assertEquals(OrderStatus.PLACED, order.status());
        assertEquals(770, order.totalCents());
        assertNull(order.cancelReason());
        assertEquals(0, order.refundCents());
    }

    @Test
    void readyThenPickedUp() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));

        orders.handle(new MarkReady(placed.id()));
        Order pickedUp = orders.handle(new PickUp(placed.id()));

        assertEquals(OrderStatus.PICKED_UP, pickedUp.status());
    }

    @Test
    void cannotPickUpBeforeReady() {
        Order placed = orders.handle(new PlaceOrder("Ana", List.of("croissant")));

        assertThrows(IllegalTransition.class, () -> orders.handle(new PickUp(placed.id())));
    }
}
EOF

w $T/api/OrderControllerIT.java <<'EOF'
package bakery.api;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import bakery.api.dto.CancelRequest;
import bakery.api.dto.OrderRequest;
import bakery.orders.Order;
import bakery.orders.OrderService;
import bakery.orders.OrderStatus;
import bakery.pricing.PriceList;
import bakery.pricing.RefundCalculator;
import bakery.support.InMemoryOrderRepository;
import bakery.support.RecordingPaymentGateway;
import java.time.Clock;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class OrderControllerIT {

    private final OrderController controller = new OrderController(new OrderService(
            new InMemoryOrderRepository(),
            new PriceList(Map.of("croissant", 350)),
            new RefundCalculator(),
            new RecordingPaymentGateway(),
            Clock.systemUTC()));

    @Test
    void deleteCancelsTheOrder() {
        Order placed = controller.place(new OrderRequest("Ana", List.of("croissant")));

        Order cancelled = controller.cancel(placed.id(), new CancelRequest("CUSTOMER_REQUEST"));

        assertEquals(OrderStatus.CANCELLED, cancelled.status());
        assertEquals(350, cancelled.refundCents());
    }

    @Test
    void unknownReasonIsRejected() {
        Order placed = controller.place(new OrderRequest("Ana", List.of("croissant")));

        assertThrows(IllegalArgumentException.class,
                () -> controller.cancel(placed.id(), new CancelRequest("CHANGED_MY_MIND")));
    }
}
EOF

w docs/orders.md <<'EOF'
# Orders

| Call | Does |
|---|---|
| POST /orders | place an order |
| POST /orders/{id}/ready | mark it ready |
| POST /orders/{id}/pick-up | hand it over |
| DELETE /orders/{id} | cancel it, with a reason, and refund it |

An order can be cancelled until it is picked up.

| Cancelled while | Refund |
|---|---|
| PLACED | all of it |
| READY | half |
EOF

w pom.xml <<'EOF'
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>example</groupId>
  <artifactId>corner-bakery</artifactId>
  <version>0.4.0</version>
  <properties>
    <maven.compiler.release>21</maven.compiler.release>
  </properties>
</project>
EOF

commit "2026-11-17T16:45:00-06:00" "Refund a cancelled order by how far it got"
git tag pr-8-head
git update-ref refs/pull/8/head pr-8-head
git checkout -q main

echo "fake repo: $repo"
git log --oneline --graph --all --decorate | sed 's/^/  /'
